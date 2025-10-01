require "test_helper"

module RandomWalker
  class LinkPickerTest < ActiveSupport::TestCase
    def build_picker(html, url: "https://example.com/start", rng: Random.new(1))
      fetcher = ->(_uri) { html }
      RandomWalker::LinkPicker.new(url: url, html_fetcher: fetcher, rng: rng)
    end

    test "returns link from document" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org/page1">Link</a>
        </body></html>
      HTML

      picker = build_picker(html)
      link = picker.next_link
      assert_equal "https://example.org/page1", link.url
      assert_equal "Link", link.label
    end

    test "resolves relative links" do
      html = <<~HTML
        <html><body>
          <a href="/relative">Relative</a>
        </body></html>
      HTML

      picker = build_picker(html, url: "https://example.com/dir/page")
      assert_equal "https://example.com/relative", picker.next_link.url
    end

    test "uses base href when present" do
      html = <<~HTML
        <html><head><base href="https://docs.example.com/" /></head><body>
          <a href="guide">Guide</a>
        </body></html>
      HTML

      picker = build_picker(html, url: "https://example.com/")
      link = picker.next_link
      assert_equal "https://docs.example.com/guide", link.url
      assert_equal "Guide", link.label
    end

    test "ignores non http links" do
      html = <<~HTML
        <html><body>
          <a href="mailto:test@example.com">Email</a>
          <a href="javascript:void(0)">JS</a>
        </body></html>
      HTML

      picker = build_picker(html)
      assert_raises(RandomWalker::LinkPicker::Error) { picker.next_link }
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
      assert_equal "Docs home", picker.next_link.label
    end

    test "returns nil label when nothing available" do
      html = <<~HTML
        <html><body>
          <a href="/docs"><img src="/img" alt="" /></a>
        </body></html>
      HTML

      picker = build_picker(html)
      assert_nil picker.next_link.label
    end
  end
end
