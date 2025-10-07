# frozen_string_literal: true

require "net/http"
require "uri"
require "nokogiri"

require_relative "page_sanitizer"
require_relative "url_safety_checker"
require_relative "link_picker"

module RandomWalker
  class PageLoader
    class Error < StandardError; end

    Result = Struct.new(:url, :label, :html, keyword_init: true)

    USER_AGENT = "RandomWalkerStartBot/1.0 (+https://example.com)".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    MAX_REDIRECTS = 5

    def load(url)
      ensure_safe!(url)
      body, final_uri = fetch_page(url)
      ensure_safe!(final_uri)

      sanitized = RandomWalker::PageSanitizer.sanitize(body, final_uri)
      Result.new(
        url: final_uri.to_s,
        label: extract_title(body) || final_uri.to_s,
        html: sanitized
      )
    rescue RandomWalker::LinkPicker::UnsafeURLError
      raise
    rescue StandardError => e
      raise Error, e.message
    end

    private

    def ensure_safe!(candidate)
      result = RandomWalker::UrlSafetyChecker.evaluate(candidate)
      return if result.safe?

      raise RandomWalker::LinkPicker::UnsafeURLError.new(candidate, result.reasons)
    end

    def fetch_page(raw_url, remaining = MAX_REDIRECTS)
      raise Error, "Too many redirects" if remaining <= 0

      uri = parse_http_url(raw_url)

      response = with_http(uri) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        http.request(request)
      end

      case response
      when Net::HTTPSuccess
        body = response.body.to_s

        if (redirect_target = extract_body_redirect(body, uri))
          ensure_safe!(redirect_target)
          return fetch_page(redirect_target, remaining - 1)
        end

        [ body, uri ]
      when Net::HTTPRedirection
        location = response["location"]
        raise Error, "Redirect without location" unless location

        next_uri = URI.join(uri.to_s, location).to_s
        ensure_safe!(next_uri)
        fetch_page(next_uri, remaining - 1)
      else
        raise Error, "HTTP #{response.code} #{response.message}"
      end
    end

    def parse_http_url(value)
      uri = value.is_a?(URI::HTTP) ? value : URI.parse(value.to_s)
      raise Error, "Unsupported URL" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      uri
    rescue URI::InvalidURIError => e
      raise Error, "Invalid URL: #{e.message}"
    end

    def with_http(uri)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| yield(http) }
    end

    def extract_body_redirect(body, base_uri)
      document = Nokogiri::HTML(body)

      refresh_node = document.css("meta[http-equiv]").find { |node| node["http-equiv"].to_s.casecmp("refresh").zero? }
      if refresh_node
        content = refresh_node["content"].to_s
        if (match = content.match(/url=(.+)/i))
          candidate = resolve_relative_url(match[1], base_uri)
          return candidate if candidate
        end
      end

      if base_uri.host&.include?("duckduckgo.com")
        redirect_message = document.at_xpath("//*[contains(text(), 'You are being redirected to the non-JavaScript site')]")
        if redirect_message
          anchor = document.at_css("a[href]")
          candidate = anchor && resolve_relative_url(anchor["href"], base_uri)
          return candidate if candidate
        end
      end

      nil
    rescue StandardError
      nil
    end

    def resolve_relative_url(href, base_uri)
      return nil unless href

      trimmed = href.to_s.strip
      return nil if trimmed.empty?

      uri = URI.parse(trimmed)
      uri = URI.join(base_uri.to_s, trimmed) if uri.relative?
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def extract_title(html)
      document = Nokogiri::HTML(html.to_s)
      title = document.at("title")&.text.to_s.strip
      title.empty? ? nil : title
    rescue StandardError
      nil
    end
  end
end
