require "test_helper"
require "uri"

module RandomWalker
  class LinkPickerTest < ActiveSupport::TestCase
    def build_picker(html, url: "https://example.com/start", rng: Random.new(1))
      fetcher = ->(_uri) { html }
      RandomWalker::LinkPicker.new(url: url, html_fetcher: fetcher, rng: rng)
    end

    def with_target_stub(picker, html:, final_url: nil, &block)
      picker.stub(:fetch_target_page, ->(url) { [ html, URI.parse(final_url || url) ] }, &block)
    end

    test "returns link from document" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org/page1">Link</a>
        </body></html>
      HTML

      picker = build_picker(html)
      with_target_stub(picker, html: "<html><body>Next</body></html>") do
        link = picker.next_link
        assert_equal "https://example.org/page1", link.url
        assert_equal "Link", link.label
        assert_includes link.html, "Next"
      end
    end

    test "resolves relative links" do
      html = <<~HTML
        <html><body>
          <a href="/relative">Relative</a>
        </body></html>
      HTML

      picker = build_picker(html, url: "https://example.com/dir/page")
      with_target_stub(picker, html: "<html><body>Next</body></html>") do
        assert_equal "https://example.com/relative", picker.next_link.url
      end
    end

    test "uses base href when present" do
      html = <<~HTML
        <html><head><base href="https://docs.example.com/" /></head><body>
          <a href="guide">Guide</a>
        </body></html>
      HTML

      picker = build_picker(html, url: "https://example.com/")
      with_target_stub(picker, html: "<html><body>Guide page</body></html>") do
        link = picker.next_link
        assert_equal "https://docs.example.com/guide", link.url
        assert_equal "Guide", link.label
      end
    end

    test "ignores non http links" do
      html = <<~HTML
        <html><body>
          <a href="mailto:test@example.com">Email</a>
          <a href="javascript:void(0)">JS</a>
        </body></html>
      HTML

      picker = build_picker(html)
      assert_raises(RandomWalker::LinkPicker::Error) do
        with_target_stub(picker, html: "<html></html>") { picker.next_link }
      end
    end

    test "raises when fetch fails" do
      fetcher = ->(_uri) { raise IOError, "boom" }

      picker = RandomWalker::LinkPicker.new(
        url: "https://example.com",
        html_fetcher: fetcher,
        rng: Random.new(1)
      )

      error = assert_raises(RandomWalker::LinkPicker::Error) { picker.next_link }
      assert_match(/Failed to fetch/, error.message)
    end

    test "rejects unsupported url schemes" do
      assert_raises(RandomWalker::LinkPicker::Error) do
        RandomWalker::LinkPicker.new(url: "ftp://example.com")
      end
    end

    test "derives label from title when text missing" do
      html = <<~HTML
        <html><body>
          <a href="/docs" title="Docs home"><span></span></a>
        </body></html>
      HTML

      picker = build_picker(html)
      with_target_stub(picker, html: "<html></html>") do
        assert_equal "Docs home", picker.next_link.label
      end
    end

    test "returns nil label when nothing available" do
      html = <<~HTML
        <html><body>
          <a href="/docs"><img src="/img" alt="" /></a>
        </body></html>
      HTML

      picker = build_picker(html)
      with_target_stub(picker, html: "<html></html>") do
        assert_nil picker.next_link.label
      end
    end

    test "honors resolved url from redirect" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org/page">Jump</a>
        </body></html>
      HTML

      picker = build_picker(html)
      target_html = "<html><body><p>Redirected</p></body></html>"

      with_target_stub(picker, html: target_html, final_url: "https://redirected.example.com/page") do
        link = picker.next_link
        assert_equal "https://redirected.example.com/page", link.url
        assert_includes link.html, "Redirected"
        assert_includes link.html, "<base"
      end
    end

    test "sanitizes returned html" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org">Link</a>
        </body></html>
      HTML

      picker = build_picker(html)
      dirty = <<~HTML
        <html>
          <head><script>alert("x")</script></head>
          <body onload="alert('test')">
            <h1>Title</h1>
          </body>
        </html>
      HTML

      with_target_stub(picker, html: dirty) do
        link = picker.next_link
        refute_includes link.html, "script"
        refute_includes link.html, "onload"
        assert_includes link.html, "<base"
      end
    end

    test "removes javascript urls" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org">Link</a>
        </body></html>
      HTML

      picker = build_picker(html)
      dirty = <<~HTML
        <html>
          <body>
            <a href="javascript:alert('x')">Bad</a>
            <img src="javascript:alert('y')" />
          </body>
        </html>
      HTML

      with_target_stub(picker, html: dirty) do
        sanitized = picker.next_link.html
        refute_includes sanitized.downcase, "javascript:alert"
      end
    end

    test "skips links that fail to fetch" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org/bad">Bad</a>
          <a href="https://example.org/good">Good</a>
        </body></html>
      HTML

      picker = build_picker(html)

      fetch_stub = lambda do |url|
        if url.include?("bad")
          raise RandomWalker::LinkPicker::Error, "broken"
        else
          [ "<html><body>ok</body></html>", URI.parse(url) ]
        end
      end

      picker.stub(:fetch_target_page, fetch_stub) do
        link = picker.next_link
        assert_equal "https://example.org/good", link.url
        assert_includes link.html, "ok"
      end
    end
  end
end
