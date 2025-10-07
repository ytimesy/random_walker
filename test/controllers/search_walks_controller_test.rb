require "test_helper"

class SearchWalksControllerTest < ActionDispatch::IntegrationTest
  test "returns search result as json" do
    result = RandomWalker::SearchWalker::Result.new(
      url: "https://example.com",
      label: "Example",
      html: "<html></html>"
    )

    mock = Minitest::Mock.new
    mock.expect(:next_link, result, [ "term" ])

    RandomWalker::SearchWalker.stub(:new, -> { mock }) do
      get search_walk_url(format: :json), params: { q: "term" }
    end

    mock.verify

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "https://example.com", body["url"]
    assert_equal "Example", body["label"]
    assert_equal "term", body["query"]
  end

  test "returns unsafe payload when blocked" do
    error = RandomWalker::LinkPicker::UnsafeURLError.new("http://evil", [ "Bad" ])

    RandomWalker::SearchWalker.stub(:new, -> { Object.new.tap { |obj| obj.define_singleton_method(:next_link) { |_term| raise error } } }) do
      get search_walk_url(format: :json), params: { q: "term" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal true, body["unsafe"]
    assert_equal [ "Bad" ], body["reasons"]
    assert_equal "http://evil", body["blocked_url"]
  end

  test "returns error when service fails" do
    RandomWalker::SearchWalker.stub(:new, -> { Object.new.tap { |obj| obj.define_singleton_method(:next_link) { |_term| raise RandomWalker::SearchWalker::Error, "failed" } } }) do
      get search_walk_url(format: :json), params: { q: "" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "failed", body["error"]
  end
end
