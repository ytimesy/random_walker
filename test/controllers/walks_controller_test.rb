require "test_helper"
require "ostruct"

class WalksControllerTest < ActionDispatch::IntegrationTest
  test "returns next url as json" do
    link = RandomWalker::LinkPicker::Link.new(url: "https://example.org", label: "Example")

    RandomWalker::LinkPicker.any_instance.stub(:next_link, link) do
      get walk_url(format: :json), params: { url: "https://example.com" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "https://example.org", body["url"]
    assert_equal "Example", body["label"]
  end

  test "returns error when picker fails" do
    RandomWalker::LinkPicker.any_instance.stub(:next_link, proc { raise RandomWalker::LinkPicker::Error.new("no links") }) do
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
      RandomWalker::LinkPicker.stub(:new, ->(url:) { OpenStruct.new(next_link: RandomWalker::LinkPicker::Link.new(url: url, label: nil)) }) do
        get walk_url(format: :json), params: { url: "" }
      end

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "https://initial.example.com", body["url"]
    ensure
      Rails.application.config.random_walker[:initial_url] = original
    end
  end
end
