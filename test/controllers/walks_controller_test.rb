require "test_helper"
require "ostruct"
require "active_support/cache"

class WalksControllerTest < ActionDispatch::IntegrationTest
  test "returns next url as json" do
    link = RandomWalker::LinkPicker::Link.new(url: "https://example.org", label: "Example", html: "<html></html>")
    picker = Minitest::Mock.new
    picker.expect(:next_link, link)
    picker.expect(:lucky_jump_triggered?, false)

    RandomWalker::LinkPicker.stub(:new, ->(**_kwargs) { picker }) do
      get walk_url(format: :json), params: { url: "https://example.com" }
    end

    picker.verify

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "https://example.org", body["url"]
    assert_equal "Example", body["label"]
    assert_equal "<html></html>", body["html"]
  end

  test "returns error when picker fails" do
    failing_picker = Object.new
    failing_picker.define_singleton_method(:next_link) do
      raise RandomWalker::LinkPicker::Error, "no links"
    end

    RandomWalker::LinkPicker.stub(:new, ->(**_kwargs) { failing_picker }) do
      get walk_url(format: :json), params: { url: "https://example.com" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "no links", body["error"]
    refute body["unsafe"]
  end

  test "marks unsafe responses with reasons" do
    unsafe_error = RandomWalker::LinkPicker::UnsafeURLError.new(
      "http://evil.test",
      [ "IP address hosts are blocked", "Suspicious top-level domain" ]
    )

    picker = Object.new
    picker.define_singleton_method(:next_link) do
      raise unsafe_error
    end

    RandomWalker::LinkPicker.stub(:new, ->(**_kwargs) { picker }) do
      get walk_url(format: :json), params: { url: "https://example.com" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal unsafe_error.message, body["error"]
    assert_equal true, body["unsafe"]
    assert_equal unsafe_error.reasons, body["reasons"]
    assert_equal unsafe_error.candidate, body["blocked_url"]
  end

  test "falls back to initial url when param blank" do
    original = Rails.application.config.random_walker[:initial_url]
    Rails.application.config.random_walker[:initial_url] = "https://initial.example.com"

    begin
      RandomWalker::LinkPicker.stub(:new, lambda { |url:, **|
        picker = Object.new
        picker.define_singleton_method(:next_link) do
          RandomWalker::LinkPicker::Link.new(url: url, label: nil, html: "<html></html>")
        end
        picker.define_singleton_method(:lucky_jump_triggered?) { false }
        picker
      }) do
        get walk_url(format: :json), params: { url: "" }
      end

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "https://initial.example.com", body["url"]
      assert_equal "<html></html>", body["html"]
    ensure
      Rails.application.config.random_walker[:initial_url] = original
    end
  end

  test "rate limits repeated walk requests" do
    original_requests = Rails.application.config.random_walker[:rate_limit_requests]
    original_window = Rails.application.config.random_walker[:rate_limit_window]
    cache = ActiveSupport::Cache.lookup_store(:memory_store)

    Rails.application.config.random_walker[:rate_limit_requests] = 1
    Rails.application.config.random_walker[:rate_limit_window] = 60

    begin
      RandomWalker::LinkPicker.stub(:new, lambda { |url:, **|
        picker = Object.new
        picker.define_singleton_method(:next_link) do
          RandomWalker::LinkPicker::Link.new(url: url, label: nil, html: "<html></html>")
        end
        picker.define_singleton_method(:lucky_jump_triggered?) { false }
        picker
      }) do
        Rails.stub(:cache, cache) do
          get walk_url(format: :json), params: { url: "https://example.com" }
          assert_response :success

          get walk_url(format: :json), params: { url: "https://example.com" }
          assert_response :too_many_requests
          body = JSON.parse(response.body)
          assert_equal "Too many walk requests. Please slow down.", body["error"]
        end
      end
    ensure
      Rails.application.config.random_walker[:rate_limit_requests] = original_requests
      Rails.application.config.random_walker[:rate_limit_window] = original_window
    end
  end

  test "passes ribbon mode to the picker" do
    picker = Object.new
    picker.define_singleton_method(:next_link) do
      RandomWalker::LinkPicker::Link.new(url: "https://example.org", label: "Ribbon", html: "<html></html>")
    end
    picker.define_singleton_method(:lucky_jump_triggered?) { false }

    RandomWalker::LinkPicker.stub(:new, ->(url:, mode:, **_kwargs) {
      assert_equal :ribbon, mode
      picker
    }) do
      get walk_url(format: :json), params: { url: "https://example.com", mode: "ribbon" }
    end

    assert_response :success
  end

  test "passes lucky jump options to the picker and returns the flag" do
    picker = Object.new
    picker.define_singleton_method(:next_link) do
      RandomWalker::LinkPicker::Link.new(url: "https://example.org/lucky", label: "Lucky", html: "<html></html>")
    end
    picker.define_singleton_method(:lucky_jump_triggered?) { true }

    RandomWalker::LinkPicker.stub(:new, ->(url:, visited:, lucky_jump:, force_lucky_jump:, **_kwargs) {
      assert_equal "https://example.com", url
      assert_equal [ "https://seen.example.org/1" ], visited
      assert_equal true, lucky_jump
      assert_equal true, force_lucky_jump
      picker
    }) do
      get walk_url(format: :json), params: {
        url: "https://example.com",
        lucky: "true",
        force_lucky_jump: "true",
        visited: [ "https://seen.example.org/1" ]
      }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["lucky_jump"]
  end

  test "passes sweet click option to the picker" do
    picker = Object.new
    picker.define_singleton_method(:next_link) do
      RandomWalker::LinkPicker::Link.new(url: "https://example.org/sweet", label: "Sweet", html: "<html></html>")
    end
    picker.define_singleton_method(:lucky_jump_triggered?) { false }

    RandomWalker::LinkPicker.stub(:new, ->(url:, sweet_click:, **_kwargs) {
      assert_equal "https://example.com", url
      assert_equal true, sweet_click
      picker
    }) do
      get walk_url(format: :json), params: {
        url: "https://example.com",
        sweet: "true"
      }
    end

    assert_response :success
  end
end
