require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "renders home" do
    get root_url

    assert_response :success
    assert_match "Random Walker", response.body
  end

  test "renders pricing" do
    get pricing_url

    assert_response :success
    assert_match "Supporter", response.body
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
