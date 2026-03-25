require "test_helper"
require "active_support/cache"

class EngagementEventsControllerTest < ActionDispatch::IntegrationTest
  test "increments support click metric" do
    cache = ActiveSupport::Cache.lookup_store(:memory_store)

    Rails.stub(:cache, cache) do
      post engagement_event_url(format: :json), params: { event_type: "support_click" }

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal true, body["ok"]
      assert_equal 1, body.dig("mission", "support_clicks")
    end
  end

  test "increments trail metrics" do
    cache = ActiveSupport::Cache.lookup_store(:memory_store)

    Rails.stub(:cache, cache) do
      post engagement_event_url(format: :json), params: { event_type: "trail_save" }
      post engagement_event_url(format: :json), params: { event_type: "trail_export" }

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body.dig("mission", "trail_exports")

      mission = RandomWalker::OneYenMission.snapshot(visitor_value_yen: 1, support_batch_yen: 100)
      assert_equal 1, mission[:trail_saves]
      assert_equal 1, mission[:trail_exports]
    end
  end

  test "rejects unsupported events" do
    post engagement_event_url(format: :json), params: { event_type: "not_real" }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "Unsupported event type.", body["error"]
  end
end
