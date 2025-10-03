require "test_helper"

module RandomWalker
  class UrlSafetyCheckerTest < ActiveSupport::TestCase
    test "https domains without suspicious signals are safe" do
      result = UrlSafetyChecker.evaluate("https://example.com/path")
      assert result.safe?
      assert_equal 0, result.score
    end

    test "ip based hosts are unsafe" do
      result = UrlSafetyChecker.evaluate("https://192.168.0.1/login")
      refute result.safe?
      assert_includes result.reasons.join(" "), "IP address"
    end

    test "suspicious tlds are unsafe" do
      result = UrlSafetyChecker.evaluate("https://phish.zip/form")
      refute result.safe?
      assert_includes result.reasons.join(" "), "Suspicious top-level domain"
    end

    test "combination of warnings crosses threshold" do
      result = UrlSafetyChecker.evaluate("http://secure-login.example.com")
      refute result.safe?
      assert_includes result.reasons.join(" "), "suspicious terms"
    end
  end
end
