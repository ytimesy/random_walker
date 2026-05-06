# frozen_string_literal: true

require "net/http"
require "nokogiri"
require "uri"

module RandomWalker
  class PageFrame
    class Error < StandardError; end

    USER_AGENT = "RandomWalkerBot/1.0 (+https://example.com)"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    MAX_REDIRECTS = 5

    def initialize(url:, html_fetcher: nil)
      @source_url = parse_url(url)
      @html_fetcher = html_fetcher || method(:fetch_with_redirects)
    end

    def html
      ensure_safe!(source_url)

      body, final_uri = normalize_fetch_result(html_fetcher.call(source_url))
      ensure_safe!(final_uri)
      render_document(body, final_uri)
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "Failed to render destination page: #{e.message}"
    end

    private

    attr_reader :source_url, :html_fetcher

    def render_document(body, final_uri)
      serialized = body.to_s
      raise Error, "Empty destination page" if serialized.strip.empty?

      document = Nokogiri::HTML(serialized)
      document.css("meta[http-equiv]").each do |node|
        node.remove if node["http-equiv"].to_s.casecmp("content-security-policy").zero?
      end
      document.css("a[href]").each do |node|
        node["target"] = "_blank"
        node["rel"] = "noopener noreferrer"
      end

      ensure_head(document).prepend_child(base_node(document, final_uri))
      document.to_html
    end

    def ensure_head(document)
      head = document.at_css("head")
      return head if head

      html = document.at_css("html")
      head = Nokogiri::XML::Node.new("head", document)

      if html
        first_child = html.children.first
        first_child ? first_child.add_previous_sibling(head) : html.add_child(head)
      else
        document.add_child(head)
      end

      head
    end

    def base_node(document, final_uri)
      node = Nokogiri::XML::Node.new("base", document)
      node["href"] = final_uri.to_s
      node
    end

    def fetch_with_redirects(uri, remaining = MAX_REDIRECTS)
      raise Error, "Too many redirects" if remaining <= 0

      response = perform_request(uri)

      case response
      when Net::HTTPSuccess
        [ response.body, uri ]
      when Net::HTTPRedirection
        location = response["location"]
        raise Error, "Redirect without location" unless location

        fetch_with_redirects(resolve_redirect_uri(uri, location), remaining - 1)
      else
        raise Error, "HTTP #{response.code} #{response.message}"
      end
    end

    def perform_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      http.request(request)
    end

    def resolve_redirect_uri(base_uri, location)
      parsed = URI.parse(location)
      parsed = URI.join(base_uri.to_s, location) if parsed.relative?
      validate_uri!(parsed)
      parsed
    rescue URI::InvalidURIError => e
      raise Error, "Invalid redirect URL: #{e.message}"
    end

    def normalize_fetch_result(raw)
      case raw
      when Array
        body, uri = raw
        [ body, validate_uri!(uri) ]
      else
        [ raw, source_url ]
      end
    end

    def parse_url(raw)
      validate_uri!(raw)
    rescue URI::InvalidURIError => e
      raise Error, "Invalid URL: #{e.message}"
    end

    def validate_uri!(value)
      uri = value.is_a?(URI::HTTP) || value.is_a?(URI::HTTPS) ? value : URI.parse(value.to_s)
      raise URI::InvalidURIError, "unsupported scheme" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      uri
    end

    def ensure_safe!(uri)
      result = RandomWalker::UrlSafetyChecker.evaluate(
        uri,
        allowed_hosts: Rails.application.config.random_walker[:allowed_hosts]
      )
      return if result.safe?

      raise Error, "Blocked unsafe URL #{uri}: #{result.reasons.join('; ')}"
    end
  end
end
