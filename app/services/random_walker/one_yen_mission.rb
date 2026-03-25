# frozen_string_literal: true

require "securerandom"

module RandomWalker
  class OneYenMission
    VISITOR_COOKIE_KEY = :random_walker_visitor_token

    CACHE_KEYS = {
      visitors: "random-walker:mission:visitors",
      support_clicks: "random-walker:mission:support-clicks",
      trail_saves: "random-walker:mission:trail-saves",
      trail_exports: "random-walker:mission:trail-exports"
    }.freeze

    CACHE_TTL = 30.days

    class << self
      def track_visit!(cookies)
        return false if cookies.permanent.signed[VISITOR_COOKIE_KEY].present?

        cookies.permanent.signed[VISITOR_COOKIE_KEY] = {
          value: SecureRandom.uuid,
          httponly: true,
          same_site: :lax
        }

        increment!(:visitors)
        true
      end

      def increment!(metric)
        key = CACHE_KEYS.fetch(metric)
        count = Rails.cache.increment(key, 1, expires_in: CACHE_TTL)
        return count if count

        count = Rails.cache.read(key).to_i + 1
        Rails.cache.write(key, count, expires_in: CACHE_TTL)
        count
      end

      def snapshot(visitor_value_yen:, support_batch_yen:)
        visitor_value = [ visitor_value_yen.to_i, 1 ].max
        support_batch = [ support_batch_yen.to_i, visitor_value ].max

        visitors = read(:visitors)
        {
          visitors: visitors,
          support_clicks: read(:support_clicks),
          trail_saves: read(:trail_saves),
          trail_exports: read(:trail_exports),
          visitor_value_yen: visitor_value,
          revenue_target_yen: visitors * visitor_value,
          suggested_support_yen: support_batch,
          suggested_support_visitors: [ support_batch / visitor_value, 1 ].max
        }
      end

      private

      def read(metric)
        Rails.cache.read(CACHE_KEYS.fetch(metric)).to_i
      end
    end
  end
end
