require "test_helper"

module RandomWalker
  class UrlSafetyCheckerTest < ActiveSupport::TestCase
    test "https domains without suspicious signals are safe" do
      result = UrlSafetyChecker.evaluate("https://example.com/path")
      assert result.safe?
      assert_equal 0, result.score
      assert_empty result.reasons
    end

    test "ip based hosts are unsafe" do
      result = UrlSafetyChecker.evaluate("https://192.168.0.1/login")
      refute result.safe?
      assert_includes result.reasons.join(" "), "IP address"
      assert result.score >= RandomWalker::UrlSafetyChecker::HIGH_RISK_PENALTY
    end

    test "suspicious tlds are unsafe" do
      result = UrlSafetyChecker.evaluate("https://phish.zip/form")
      refute result.safe?
      assert_includes result.reasons.join(" "), "Suspicious top-level domain"
      assert result.score >= RandomWalker::UrlSafetyChecker::HIGH_RISK_PENALTY
    end

    test "combination of warnings crosses threshold" do
      result = UrlSafetyChecker.evaluate("http://secure-login.example.com")
      assert result.safe?
      assert_equal 2, result.score
      assert_includes result.reasons.join(" "), "URL must use HTTPS"
      assert_includes result.reasons.join(" "), "suspicious terms"
    end
  end
end
