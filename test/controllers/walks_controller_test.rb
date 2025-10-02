require "test_helper"
require "ostruct"

class WalksControllerTest < ActionDispatch::IntegrationTest
  test "returns next url as json" do
    link = RandomWalker::LinkPicker::Link.new(url: "https://example.org", label: "Example", html: "<html></html>")
    picker = Minitest::Mock.new
    picker.expect(:next_link, link)

    RandomWalker::LinkPicker.stub(:new, ->(url:) { picker }) do
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

    RandomWalker::LinkPicker.stub(:new, ->(url:) { failing_picker }) do
      get walk_url(format: :json), params: { url: "https://example.com" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "no links", body["error"]
  end

  test "falls back to initial url when param blank" do
    original = Rails.application.config.random_walker[:initial_url]
    Rails.application.config.random_walker[:initial_url] = "https://initial.example.com"

    begin
      RandomWalker::LinkPicker.stub(:new, ->(url:) { OpenStruct.new(next_link: RandomWalker::LinkPicker::Link.new(url: url, label: nil, html: "<html></html>")) }) do
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
end
