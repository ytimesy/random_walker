# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "uri"
require "nokogiri"

require_relative "page_sanitizer"
require_relative "url_safety_checker"
require_relative "link_picker"

module RandomWalker
  class SearchWalker
    class Error < StandardError; end

    USER_AGENT = "RandomWalkerSearchBot/1.0 (+https://example.com)".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    MAX_REDIRECTS = 5
    API_ENDPOINT = URI("https://api.duckduckgo.com/")

    Result = Struct.new(:url, :label, :html, keyword_init: true)

    def initialize(rng: Random.new, http_client: nil)
      @rng = rng
      @http_client = http_client
    end

    def next_link(query)
      term = query.to_s.strip
      raise Error, "Search term is required" if term.empty?

      candidates = fetch_candidates(term)
      raise Error, "No search results found" if candidates.empty?

      attempt = 0
      last_error = nil

      candidates.shuffle(random: rng).each do |candidate|
        attempt += 1

        begin
          ensure_safe!(candidate[:url])
          html, final_uri = fetch_page(candidate[:url])
          ensure_safe!(final_uri)
          sanitized = RandomWalker::PageSanitizer.sanitize(html, final_uri)

          return Result.new(
            url: final_uri.to_s,
            label: candidate[:label],
            html: sanitized
          )
        rescue StandardError => e
          last_error = e
          next
        end
      end

      raise(last_error || Error.new("No safe search results"))
    end

    private

    attr_reader :rng

    def fetch_candidates(term)
      response = perform_api_request(term)
      raise Error, "Search request failed" unless response.is_a?(Net::HTTPSuccess)

      payload = parse_json(response.body)

      candidates = []
      Array(payload["RelatedTopics"]).each do |topic|
        candidates.concat(Array(flatten_topic(topic)))
      end

      Array(payload["Results"]).each do |result|
        next unless result.is_a?(Hash)

        url = result["FirstURL"] || result["Redirect"]
        next unless url

        candidates << {
          url: normalize_result_url(url),
          label: normalize_label(result["Text"] || result["Result"] || result["Title"])
        }
      end

      if (fallback = fallback_candidate(payload))
        candidates << fallback
      end

      deduplicate_candidates(candidates)
    end

    def perform_api_request(term)
      uri = API_ENDPOINT.dup
      uri.query = URI.encode_www_form(q: term, format: "json", no_redirect: 1, no_html: 1)

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT

      with_http(uri) { |http| http.request(request) }
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

    def with_http(uri)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| yield(http) }
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def flatten_topic(topic)
      if topic.is_a?(Hash)
        if topic["FirstURL"]
          [ { url: normalize_result_url(topic["FirstURL"]), label: normalize_label(topic["Text"]) } ]
        elsif topic["Topics"]
          Array(topic["Topics"]).flat_map { |subtopic| flatten_topic(subtopic) }
        else
          []
        end
      else
        []
      end
    end

    def ensure_safe!(candidate)
      result = RandomWalker::UrlSafetyChecker.evaluate(candidate)
      return if result.safe?

      raise RandomWalker::LinkPicker::UnsafeURLError.new(candidate, result.reasons)
    end

    def normalize_result_url(raw_url, depth = 0)
      return raw_url if depth >= 5

      uri = URI.parse(raw_url)
      if uri.host&.include?("duckduckgo.com")
        params = URI.decode_www_form(uri.query.to_s).to_h
        expanded = params["uddg"] || params["rut"]
        if expanded && !expanded.empty?
          decoded = CGI.unescape(expanded)
          return normalize_result_url(decoded, depth + 1)
        end
      end

      raw_url
    rescue URI::InvalidURIError
      raw_url
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

    def parse_http_url(value)
      uri = value.is_a?(URI::HTTP) ? value : URI.parse(value.to_s)
      raise Error, "Unsupported URL" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      uri
    rescue URI::InvalidURIError => e
      raise Error, "Invalid URL: #{e.message}"
    end

    def deduplicate_candidates(candidates)
      seen = {}

      candidates.filter_map do |candidate|
        next unless candidate.is_a?(Hash)

        url = candidate[:url].to_s.strip
        next if url.empty? || seen[url]

        seen[url] = true
        { url:, label: normalize_label(candidate[:label]) }
      end
    end

    def normalize_label(value)
      label = value.to_s.strip
      label.empty? ? nil : label
    end

    def fallback_candidate(payload)
      redirect = payload["Redirect"].to_s.strip
      if !redirect.empty?
        return {
          url: normalize_result_url(redirect),
          label: normalize_label(payload["Heading"]) || normalize_label(payload["Redirect"])
        }
      end

      abstract_url = payload["AbstractURL"].to_s.strip
      return if abstract_url.empty?

      {
        url: normalize_result_url(abstract_url),
        label: normalize_label(payload["Heading"]) || normalize_label(payload["AbstractText"])
      }
    rescue StandardError
      nil
    end
  end
end
