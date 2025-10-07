require "test_helper"

class PreviewsControllerTest < ActionDispatch::IntegrationTest
  test "returns preview json" do
    page = RandomWalker::PageLoader::Result.new(
      url: "https://example.com",
      label: "Example",
      html: "<html></html>"
    )

    loader = Minitest::Mock.new
    loader.expect(:load, page, [ "https://example.com" ])

    RandomWalker::PageLoader.stub(:new, -> { loader }) do
      get preview_path(format: :json), params: { url: "https://example.com" }
    end

    loader.verify

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "https://example.com", body["url"]
    assert_equal "Example", body["label"]
  end

  test "returns unsafe payload" do
    error = RandomWalker::LinkPicker::UnsafeURLError.new("http://evil", [ "Bad" ])

    RandomWalker::PageLoader.stub(:new, -> { Object.new.tap { |obj| obj.define_singleton_method(:load) { |_url| raise error } } }) do
      get preview_path(format: :json), params: { url: "http://evil" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal true, body["unsafe"]
    assert_equal [ "Bad" ], body["reasons"]
    assert_equal "http://evil", body["blocked_url"]
  end

  test "returns error on failure" do
    RandomWalker::PageLoader.stub(:new, -> { Object.new.tap { |obj| obj.define_singleton_method(:load) { |_url| raise RandomWalker::PageLoader::Error, "failed" } } }) do
      get preview_path(format: :json), params: { url: "" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "failed", body["error"]
  end
end
