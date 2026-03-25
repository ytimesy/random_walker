require "test_helper"
require "uri"

module RandomWalker
  class LinkPickerTest < ActiveSupport::TestCase
    def build_picker(html, url: "https://example.com/start", rng: Random.new(1), mode: :default, visited: [], sweet_click: false, lucky_jump: false, force_lucky_jump: false, lucky_jump_chance: RandomWalker::LinkPicker::LUCKY_JUMP_CHANCE)
      fetcher = ->(_uri) { html }
      RandomWalker::LinkPicker.new(
        url: url,
        html_fetcher: fetcher,
        rng: rng,
        mode: mode,
        visited: visited,
        sweet_click: sweet_click,
        lucky_jump: lucky_jump,
        force_lucky_jump: force_lucky_jump,
        lucky_jump_chance: lucky_jump_chance
      )
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
      target_html = <<~HTML
        <html>
          <head>
            <title>Next stop</title>
            <meta name="description" content="A soft preview of the next place to wander into.">
          </head>
          <body>Next</body>
        </html>
      HTML

      with_target_stub(picker, html: target_html) do
        link = picker.next_link
        assert_equal "https://example.org/page1", link.url
        assert_equal "Link", link.label
        assert_equal "Next stop", link.title
        assert_equal "A soft preview of the next place to wander into.", link.description
        assert_equal "example.org", link.host
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
      with_target_stub(picker, html: "<html><head><title>Guide page</title></head><body>Guide page</body></html>") do
        link = picker.next_link
        assert_equal "https://docs.example.com/guide", link.url
        assert_equal "Guide", link.label
        assert_equal "Guide page", link.title
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
      with_target_stub(picker, html: "<html><head><title>Docs page</title></head></html>") do
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
      target_html = <<~HTML
        <html>
          <head>
            <title>Redirected page</title>
            <meta property="og:site_name" content="Redirected Example">
          </head>
          <body><p>Redirected preview paragraph with enough detail to stand on its own.</p></body>
        </html>
      HTML

      with_target_stub(picker, html: target_html, final_url: "https://redirected.example.com/page") do
        link = picker.next_link
        assert_equal "https://redirected.example.com/page", link.url
        assert_equal "Redirected page", link.title
        assert_equal "Redirected Example", link.site_name
        assert_match(/Redirected preview paragraph/, link.description)
      end
    end

    test "extracts preview metadata from meta tags" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org">Link</a>
        </body></html>
      HTML

      picker = build_picker(html)
      dirty = <<~HTML
        <html>
          <head>
            <script>alert("x")</script>
            <title>Hidden title</title>
            <meta property="og:title" content="Preview title">
            <meta name="description" content="Preview description">
          </head>
          <body onload="alert('test')">
            <h1>Title</h1>
          </body>
        </html>
      HTML

      with_target_stub(picker, html: dirty) do
        link = picker.next_link
        assert_equal "Preview title", link.title
        assert_equal "Preview description", link.description
      end
    end

    test "falls back to paragraph text when description metadata is missing" do
      html = <<~HTML
        <html><body>
          <a href="https://example.org">Link</a>
        </body></html>
      HTML

      picker = build_picker(html)
      dirty = <<~HTML
        <html>
          <head>
            <title>Paragraph fallback</title>
          </head>
          <body>
            <p>tiny</p>
            <p>This is the first paragraph with enough detail to become a preview description for the walker interface.</p>
          </body>
        </html>
      HTML

      with_target_stub(picker, html: dirty) do
        link = picker.next_link
        assert_equal "Paragraph fallback", link.title
        assert_match(/first paragraph with enough detail/, link.description)
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
        assert_equal "Good", link.label
        assert_equal "example.org", link.host
      end
    end

    test "skips links flagged as unsafe" do
      html = <<~HTML
        <html><body>
          <a href="https://192.168.1.1/phish">Bad</a>
          <a href="https://example.com/good">Good</a>
        </body></html>
      HTML

      picker = build_picker(html)

      fetch_stub = ->(url) { [ "<html><body>#{url}</body></html>", URI.parse(url) ] }

      picker.stub(:fetch_target_page, fetch_stub) do
        link = picker.next_link
        assert_equal "https://example.com/good", link.url
      end
    end

    test "raises when all links are unsafe" do
      html = <<~HTML
        <html><body>
          <a href="https://192.168.1.1/phish">Bad</a>
        </body></html>
      HTML

      picker = build_picker(html)

      error = assert_raises(RandomWalker::LinkPicker::UnsafeURLError) do
        picker.stub(:fetch_target_page, ->(url) { [ "<html></html>", URI.parse(url) ] }) do
          picker.next_link
        end
      end

      assert_match(/Blocked unsafe URL/, error.message)
      assert_equal "https://192.168.1.1/phish", error.candidate
      assert_includes error.reasons.join(";"), "IP address"
    end

    test "ribbon mode prefers same-host links first" do
      html = <<~HTML
        <html><body>
          <a href="https://outside.example.org/page">Outside</a>
          <a href="/inside">Inside</a>
        </body></html>
      HTML

      picker = build_picker(html, url: "https://example.com/start", mode: :ribbon)

      with_target_stub(picker, html: "<html><body>Next</body></html>") do
        assert_equal "https://example.com/inside", picker.next_link.url
      end
    end

    test "ribbon mode prefers expressive labels over empty labels" do
      html = <<~HTML
        <html><body>
          <a href="/image-only"><img src="/img" alt="" /></a>
          <a href="/story">Read story</a>
        </body></html>
      HTML

      picker = build_picker(html, url: "https://example.com/start", mode: :ribbon)

      with_target_stub(picker, html: "<html><head><title>Next</title></head><body>Next</body></html>") do
        assert_equal "https://example.com/story", picker.next_link.url
      end
    end

    test "lucky jump prioritizes fresh external domains when triggered" do
      html = <<~HTML
        <html><body>
          <a href="/inside">Inside</a>
          <a href="https://seen.example.org/known">Seen outside</a>
          <a href="https://new.example.net/spark">Fresh outside</a>
        </body></html>
      HTML

      picker = build_picker(
        html,
        url: "https://example.com/start",
        visited: [ "https://seen.example.org/older" ],
        lucky_jump: true,
        force_lucky_jump: true
      )

      with_target_stub(picker, html: "<html><head><title>Next</title></head><body>Next</body></html>") do
        link = picker.next_link
        assert_equal "https://new.example.net/spark", link.url
        assert picker.lucky_jump_triggered?
      end
    end

    test "sweet click prefers readable article links over utility links" do
      html = <<~HTML
        <html><body>
          <a href="/login">Login</a>
          <a href="/guides/cute-walker-story">Read the cute walker story</a>
          <a href="/download-guide.pdf">Download guide</a>
        </body></html>
      HTML

      picker = build_picker(html, url: "https://example.com/start", sweet_click: true)

      with_target_stub(picker, html: "<html><head><title>Next</title></head><body>Next</body></html>") do
        assert_equal "https://example.com/guides/cute-walker-story", picker.next_link.url
      end
    end
  end
end
