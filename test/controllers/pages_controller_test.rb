require "test_helper"
require "active_support/cache"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "renders home" do
    get root_url

    assert_response :success
    assert_match "Random Walker", response.body
    assert_match "Saved Trails", response.body
    assert_match "Become a supporter", response.body
    assert_match "1 Yen Mission", response.body
  end

  test "counts a unique visitor once per browser" do
    cache = ActiveSupport::Cache.lookup_store(:memory_store)

    Rails.stub(:cache, cache) do
      get root_url
      get root_url

      mission = RandomWalker::OneYenMission.snapshot(visitor_value_yen: 1, support_batch_yen: 100)
      assert_equal 1, mission[:visitors]
    end
  end

  test "renders pricing" do
    get pricing_url

    assert_response :success
    assert_match "Supporter", response.body
    assert_match "Become a supporter", response.body
  end

  test "renders privacy" do
    get privacy_url

    assert_response :success
    assert_match "Privacy policy draft", response.body
  end

  test "renders terms" do
    get terms_url

    assert_response :success
    assert_match "Terms of service draft", response.body
  end
end
