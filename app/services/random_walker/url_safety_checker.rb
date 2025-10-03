# frozen_string_literal: true

require "uri"

module RandomWalker
  class UrlSafetyChecker
    Result = Data.define(:safe?, :score, :reasons)

    SUSPICIOUS_TLDS = %w[
      zip review country stream download gq work men loan click link
    ].freeze

    SUSPICIOUS_KEYWORDS = %w[
      login verify update account secure free gift winner bitcoin crypto invest
    ].freeze

    MAX_SAFE_SCORE = 1

    def self.evaluate(uri)
      new(uri).evaluate
    end

    def initialize(uri)
      @uri = normalize(uri)
    end

    def evaluate
      reasons = []
      score = 0

      unless https?
        reasons << "URL must use HTTPS"
        score += 1
      end

      if ip_host?
        reasons << "IP address hosts are blocked"
        score += 2
      end

      if suspicious_tld?
        reasons << "Suspicious top-level domain"
        score += 2
      end

      keyword_hits = suspicious_keyword_hits
      unless keyword_hits.empty?
        reasons << "Contains suspicious terms: #{keyword_hits.join(", ")}"
        score += 1
      end

      Result.new(safe?: score <= MAX_SAFE_SCORE, score: score, reasons: reasons)
    rescue URI::InvalidURIError => e
      Result.new(safe?: false, score: Float::INFINITY, reasons: [ "Invalid URL: #{e.message}" ])
    end

    private

    attr_reader :uri

    def normalize(candidate)
      return candidate if candidate.is_a?(URI::HTTP) || candidate.is_a?(URI::HTTPS)

      string = candidate.to_s
      raise URI::InvalidURIError, "empty url" if string.strip.empty?

      parsed = URI.parse(string)
      unless parsed.is_a?(URI::HTTP) || parsed.is_a?(URI::HTTPS)
        raise URI::InvalidURIError, "unsupported scheme"
      end

      parsed
    end

    def https?
      uri.scheme == "https"
    end

    def ip_host?
      return false unless uri.host

      uri.host.match?(/\A(?:\d{1,3}\.){3}\d{1,3}\z/)
    end

    def suspicious_tld?
      host = uri.host.to_s.downcase
      tld = host.split(".").last
      SUSPICIOUS_TLDS.include?(tld)
    end

    def suspicious_keyword_hits
      haystack = [ uri.host, uri.path, uri.query ].compact.join(" ").downcase
      SUSPICIOUS_KEYWORDS.select { |keyword| haystack.include?(keyword) }
    end
  end
end
