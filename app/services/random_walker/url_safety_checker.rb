# frozen_string_literal: true

require "uri"

module RandomWalker
  class UrlSafetyChecker
    Result = Struct.new(:safe?, :score, :reasons, keyword_init: true)

    SUSPICIOUS_TLDS = %w[
      zip review country stream download gq work men loan click link
    ].freeze

    SUSPICIOUS_KEYWORDS = %w[
      login verify update account secure free gift winner bitcoin crypto invest
    ].freeze

    HTTPS_PENALTY = 1
    KEYWORD_PENALTY = 1
    HIGH_RISK_PENALTY = 5

    def self.evaluate(uri, allowed_hosts: nil)
      new(uri, allowed_hosts: allowed_hosts).evaluate
    end

    def initialize(uri, allowed_hosts: nil)
      @uri = normalize(uri)
      @allowed_hosts = normalize_allowed_hosts(allowed_hosts)
    end

    def evaluate
      warnings = []
      high_risk_reasons = []
      score = 0

      if !https?
        warnings << "URL must use HTTPS"
        score += HTTPS_PENALTY
      end

      keyword_hits = suspicious_keyword_hits
      unless keyword_hits.empty?
        warnings << "Contains suspicious terms: #{keyword_hits.join(", ")}"
        score += KEYWORD_PENALTY
      end

      high_risk_reasons << "Host is not in the public allowlist" if allowlist_enabled? && !allowed_host?
      high_risk_reasons << "IP address hosts are blocked" if ip_host?
      high_risk_reasons << "Suspicious top-level domain" if suspicious_tld?

      if high_risk_reasons.any?
        reasons = high_risk_reasons + warnings
        score += HIGH_RISK_PENALTY * high_risk_reasons.size
        Result.new(safe?: false, score: score, reasons: reasons)
      else
        Result.new(safe?: true, score: score, reasons: warnings)
      end
    rescue URI::InvalidURIError => e
      Result.new(safe?: false, score: Float::INFINITY, reasons: [ "Invalid URL: #{e.message}" ])
    end

    private

    attr_reader :uri, :allowed_hosts

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

    def normalize_allowed_hosts(value)
      Array(value).filter_map do |host|
        normalized = host.to_s.strip.downcase
        normalized unless normalized.empty?
      end
    end

    def allowlist_enabled?
      allowed_hosts.any?
    end

    def allowed_host?
      host = uri.host.to_s.downcase
      return false if host.empty?

      allowed_hosts.any? do |allowed|
        host == allowed || host.end_with?(".#{allowed}")
      end
    end
  end
end
