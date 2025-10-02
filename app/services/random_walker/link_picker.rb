# frozen_string_literal: true

require "nokogiri"
require "net/http"
require "set"
require "uri"

module RandomWalker
  class LinkPicker
    class Error < StandardError; end

    Link = Data.define(:url, :label, :html)

    USER_AGENT = "RandomWalkerBot/1.0 (+https://example.com)".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    MAX_REDIRECTS = 5

    def initialize(url:, visited: [], html_fetcher: nil, rng: Random.new)
      @source_url = parse_source_url(url)
      @effective_url = @source_url
      @fetcher = html_fetcher || method(:fetch_with_redirects)
      @rng = rng
      @visited_urls = normalize_visited(visited)
    end

    def next_url
      next_link.url
    end

    def next_link
      links = extract_links
      raise Error, "No navigable links found" if links.empty?

      last_error = nil

      links.shuffle(random: @rng).each do |candidate|
        next if visited?(candidate.url)

        begin
          body, final_uri = fetch_target_page(candidate.url)
          resolved_uri = coerce_uri(final_uri) || parse_source_url(candidate.url)
          next if visited?(resolved_uri)
          sanitized = sanitize_for_embed(body, resolved_uri)

          return Link.new(
            url: resolved_uri.to_s,
            label: candidate.label,
            html: sanitized
          )
        rescue Error => e
          last_error = e
        end
      end

      raise(last_error || Error.new("No navigable links found"))
    end

    private

    attr_reader :source_url, :effective_url, :fetcher, :rng, :visited_urls

    def extract_links
      document = Nokogiri::HTML(fetch_document)
      base_href = document.at("base[href]")&.[]("href")
      base = absolutize(base_href) if base_href
      candidates = document.css("a[href]").filter_map do |node|
        absolute = absolutize(node["href"], base)
        next unless absolute

        Link.new(url: absolute.to_s, label: link_label(node), html: nil)
      end
      candidates.uniq { |link| link.url }
    end

    def fetch_document
      raw, final_uri = normalize_fetch_result(fetcher.call(source_url))
      @effective_url = final_uri
      raw
    rescue StandardError => e
      raise Error, "Failed to fetch #{source_url}: #{e.message}"
    end

    def absolutize(raw_href, base = nil)
      return nil unless raw_href

      href = raw_href.strip
      return nil if href.empty?

      candidate = begin
        uri = URI.parse(href)
        if uri.relative?
          absolute_base = base || effective_url
          URI.join(absolute_base.to_s, href)
        else
          uri
        end
      rescue URI::InvalidURIError
        nil
      end

      return nil unless candidate

      candidate.fragment = nil
      return nil unless candidate.is_a?(URI::HTTP) || candidate.is_a?(URI::HTTPS)

      candidate
    end

    def link_label(node)
      text = node.text.to_s.gsub(/\s+/, " ").strip
      return text unless text.empty?

      title = node["title"].to_s.strip
      return title unless title.empty?

      nil
    end

    def parse_source_url(raw)
      return raw if raw.is_a?(URI::HTTP) || raw.is_a?(URI::HTTPS)

      unless raw.is_a?(String) && !raw.strip.empty?
        raise Error, "URL is required"
      end

      uri = URI.parse(raw)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        raise Error, "Unsupported URL scheme"
      end

      uri
    rescue URI::InvalidURIError => e
      raise Error, "Invalid URL: #{e.message}"
    end

    def fetch_target_page(raw_url)
      target_uri = parse_source_url(raw_url)
      fetch_http(target_uri)
    rescue StandardError => e
      raise Error, "Failed to fetch #{raw_url}: #{e.message}"
    end

    def fetch_with_redirects(url)
      fetch_http(parse_source_url(url))
    end

    def fetch_http(uri, remaining = MAX_REDIRECTS)
      raise Error, "Too many redirects" if remaining <= 0

      response = perform_request(uri)

      case response
      when Net::HTTPSuccess
        [ response.body, uri ]
      when Net::HTTPRedirection
        location = response["location"]
        raise Error, "Redirect without location" unless location

        next_uri = resolve_redirect_uri(uri, location)
        validate_redirect_uri!(next_uri)
        fetch_http(next_uri, remaining - 1)
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

    def validate_redirect_uri!(uri)
      raise Error, "Redirected to unsupported scheme" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    end

    def resolve_redirect_uri(base_uri, location)
      parsed = parse_uri_string(location)
      parsed = URI.join(base_uri.to_s, location) if parsed && parsed.relative?
      parsed
    rescue URI::InvalidURIError
      nil
    end

    def normalize_fetch_result(raw)
      case raw
      when Array
        body, uri = raw
        [ body, coerce_uri(uri) || source_url ]
      else
        [ raw, source_url ]
      end
    end

    def coerce_uri(value)
      case value
      when URI::HTTP, URI::HTTPS
        value
      when String
        parse_uri_string(value)
      end
    rescue URI::InvalidURIError
      nil
    end

    def parse_uri_string(raw)
      stripped = raw.to_s.strip
      attempt_parse(stripped) || attempt_parse(stripped.split(/\s+/).first)
    end

    def attempt_parse(candidate)
      return nil unless candidate && !candidate.empty?

      parsed = URI.parse(candidate)
      return parsed if parsed.is_a?(URI::HTTP) || parsed.is_a?(URI::HTTPS)

      nil
    rescue URI::InvalidURIError
      nil
    end

    def normalize_visited(value)
      Array(value).filter_map do |item|
        candidate = coerce_uri(item)
        candidate&.to_s
      end.to_set
    end

    def visited?(candidate)
      return false unless candidate

      visited_urls.include?(candidate.to_s)
    end

    def sanitize_for_embed(html, base_uri)
      serialized = html.to_s
      raise Error, "Empty response" if serialized.strip.empty?

      document = Nokogiri::HTML(serialized)

      document.css("script, iframe, frame, frameset, object, embed").remove
      document.css("meta[http-equiv]").each do |node|
        node.remove if node["http-equiv"].to_s.casecmp("refresh").zero?
      end

      document.css("*[href], *[src]").each do |node|
        %w[href src].each do |attribute|
          value = node[attribute]
          next unless value

          stripped = value.strip.downcase
          node.remove_attribute(attribute) if stripped.start_with?("javascript:")
        end
      end

      document.traverse do |node|
        next unless node.element?

        node.attribute_nodes.each do |attribute|
          node.remove_attribute(attribute.name) if attribute.name.downcase.start_with?("on")
        end
      end

      if base_uri
        head = document.at("head")
        unless head
          head = Nokogiri::XML::Node.new("head", document)
          document.root&.children&.first ? document.root.children.first.add_previous_sibling(head) : document.root&.add_child(head)
        end

        if head
          base_tag = head.at("base")
          unless base_tag
            base_tag = Nokogiri::XML::Node.new("base", document)
            head.prepend_child(base_tag)
          end
          base_tag["href"] = base_uri.to_s
        end
      end

      document.to_html
    end
  end
end
