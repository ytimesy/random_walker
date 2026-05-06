require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "renders home" do
    get root_url
    assert_response :success
    assert_match "Random Walker", response.body
    assert_match "Destination URL", response.body
    assert_match "walker-preview-frame", response.body
    assert_match "/walk/preview", response.body
    assert_match "Research Mode", response.body
    assert_match "Export Markdown", response.body
    assert_match "Import JSON", response.body
    assert_match "Report Items", response.body
    assert_match "Saved Trails", response.body
    assert_match "Keep trails in this browser", response.body
    refute_match "Become a supporter", response.body
  end

  test "renders privacy" do
    get privacy_url
    assert_response :success
    assert_match "Privacy policy draft", response.body
    assert_match "local browser storage", response.body
  end

  test "renders terms" do
    get terms_url
    assert_response :success
    assert_match "Terms of service draft", response.body
    assert_match "No accounts or billing", response.body
  end
end
