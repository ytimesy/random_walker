# frozen_string_literal: true

require "nokogiri"
require "open-uri"
require "uri"

module RandomWalker
  class LinkPicker
    class Error < StandardError; end

    Link = Data.define(:url, :label)

    USER_AGENT = "RandomWalkerBot/1.0 (+https://example.com)".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5

    def initialize(url:, html_fetcher: nil, rng: Random.new)
      @source_url = parse_source_url(url)
      @fetcher = html_fetcher || method(:fetch_html)
      @rng = rng
    end

    def next_url
      next_link.url
    end

    def next_link
      links = extract_links
      raise Error, "No navigable links found" if links.empty?

      links.sample(random: @rng)
    end

    private

    attr_reader :source_url, :fetcher, :rng

    def extract_links
      document = Nokogiri::HTML(fetch_document)
      base_href = document.at("base[href]")&.[]("href")
      base = absolutize(base_href) if base_href
      candidates = document.css("a[href]").filter_map do |node|
        absolute = absolutize(node["href"], base)
        next unless absolute

        Link.new(url: absolute.to_s, label: link_label(node))
      end
      candidates.uniq { |link| link.url }
    end

    def fetch_document
      fetcher.call(source_url)
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
          absolute_base = base || source_url
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

    def fetch_html(uri)
      URI.open(
        uri,
        "User-Agent" => USER_AGENT,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |io| io.read }
    end
  end
end
