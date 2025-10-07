require "test_helper"
require "uri"

module RandomWalker
  class PageLoaderTest < ActiveSupport::TestCase
    test "loads and sanitizes page" do
      loader = PageLoader.new

      loader.stub(:fetch_page, ->(_url) { [ "<html><head><title>Example</title></head><body>OK</body></html>", URI.parse("https://example.com") ] }) do
        result = loader.load("https://example.com")
        assert_equal "https://example.com", result.url
        assert_equal "Example", result.label
        assert_includes result.html, "OK"
      end
    end

    test "raises unsafe error for blocked url" do
      loader = PageLoader.new

      loader.stub(:fetch_page, ->(_url) { [ "", URI.parse("https://example.com") ] }) do
        assert_raises(RandomWalker::LinkPicker::UnsafeURLError) do
          loader.load("https://192.168.0.1")
        end
      end
    end

    test "extracts redirect target from duckduckgo interstitial" do
      loader = PageLoader.new
      body = <<~HTML
        <html><body>
          <p>You are being redirected to the non-JavaScript site.</p>
          <a href="https://example.org/real">Click here if it doesn't happen automatically.</a>
        </body></html>
      HTML
      base = URI.parse("https://duckduckgo.com/redirect")

      target = loader.send(:extract_body_redirect, body, base)
      assert_equal "https://example.org/real", target
    end
  end
end
