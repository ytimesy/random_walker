require "test_helper"
require "uri"
require "cgi"

module RandomWalker
  class SearchWalkerTest < ActiveSupport::TestCase
    def http_success(body)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, body)
      response
    end

    test "returns sanitized search result" do
      walker = SearchWalker.new(rng: Random.new(1))

      walker.stub(:fetch_candidates, ->(_) do
        [ { url: "https://example.com/page", label: "Example" } ]
      end) do
        walker.stub(:fetch_page, ->(_) { [ "<html><body>Example</body></html>", URI.parse("https://example.com/page") ] }) do
          result = walker.next_link("example")
          assert_equal "https://example.com/page", result.url
          assert_equal "Example", result.label
          assert_includes result.html, "Example"
        end
      end
    end

    test "raises error when no candidates" do
      walker = SearchWalker.new

      walker.stub(:fetch_candidates, ->(_) { [] }) do
        assert_raises(SearchWalker::Error) { walker.next_link("nothing") }
      end
    end

    test "raises unsafe error when url blocked" do
      walker = SearchWalker.new

      walker.stub(:fetch_candidates, ->(_) do
        [ { url: "http://192.168.0.1/phish", label: "Bad" } ]
      end) do
        assert_raises(RandomWalker::LinkPicker::UnsafeURLError) do
          walker.next_link("malware")
        end
      end
    end

    test "normalizes duckduckgo redirect urls" do
      walker = SearchWalker.new
      encoded = "https://example.org/path?q=1"
      ddg = "https://duckduckgo.com/l/?uddg=#{CGI.escape(encoded)}"

      url = walker.send(:normalize_result_url, ddg)
      assert_equal encoded, url

      direct = walker.send(:normalize_result_url, "https://example.com")
      assert_equal "https://example.com", direct

      rut = "https://duckduckgo.com/l/?rut=#{CGI.escape(ddg)}"
      url_from_rut = walker.send(:normalize_result_url, rut)
      assert_equal encoded, url_from_rut
    end

    test "extracts redirect target from duckduckgo interstitial" do
      walker = SearchWalker.new
      body = <<~HTML
        <html><body>
          <p>You are being redirected to the non-JavaScript site.</p>
          <a href="https://example.org/real">Click here if it doesn't happen automatically.</a>
        </body></html>
      HTML
      base = URI.parse("https://duckduckgo.com/redirect")

      target = walker.send(:extract_body_redirect, body, base)
      assert_equal "https://example.org/real", target
    end

    test "fetch_candidates uses results array" do
      walker = SearchWalker.new
      payload = {
        "Results" => [
          { "FirstURL" => "https://example.com/result", "Text" => "Result text" }
        ]
      }

      walker.stub(:perform_api_request, ->(_) { http_success(payload.to_json) }) do
        candidates = walker.send(:fetch_candidates, "term")
        assert_equal 1, candidates.size
        assert_equal "https://example.com/result", candidates.first[:url]
        assert_equal "Result text", candidates.first[:label]
      end
    end

    test "fetch_candidates falls back to abstract url" do
      walker = SearchWalker.new
      payload = {
        "RelatedTopics" => [],
        "Results" => [],
        "AbstractURL" => "https://example.net/info",
        "Heading" => "Example Heading",
        "AbstractText" => "Example abstract"
      }

      walker.stub(:perform_api_request, ->(_) { http_success(payload.to_json) }) do
        candidates = walker.send(:fetch_candidates, "term")
        assert_equal 1, candidates.size
        assert_equal "https://example.net/info", candidates.first[:url]
        assert_equal "Example Heading", candidates.first[:label]
      end
    end
  end
end
