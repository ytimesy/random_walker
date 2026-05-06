require "test_helper"

module RandomWalker
  class PageFrameTest < ActiveSupport::TestCase
    test "injects base href and opens links outside the frame" do
      fetcher = lambda do |_url|
        [
          <<~HTML,
            <!doctype html>
            <html>
              <head>
                <title>Example</title>
                <meta http-equiv="Content-Security-Policy" content="default-src 'self'">
              </head>
              <body>
                <a href="/next">Next</a>
              </body>
            </html>
          HTML
          URI.parse("https://example.com/start")
        ]
      end

      html = PageFrame.new(url: "https://example.com/start", html_fetcher: fetcher).html
      document = Nokogiri::HTML(html)

      assert_equal "https://example.com/start", document.at_css("base")["href"]
      assert_nil document.at_css("meta[http-equiv='Content-Security-Policy']")
      assert_equal "_blank", document.at_css("a")["target"]
      assert_equal "noopener noreferrer", document.at_css("a")["rel"]
    end
  end
end
