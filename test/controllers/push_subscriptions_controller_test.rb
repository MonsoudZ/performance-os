require "test_helper"

class PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "creates a subscription for the user" do
    assert_difference "PushSubscription.count", 1 do
      post push_subscriptions_path, params: subscription_params
    end

    assert_response :created
    assert_equal @user, PushSubscription.find_by(endpoint: "https://push.example/abc").user
  end

  test "is idempotent on the same endpoint" do
    2.times { post push_subscriptions_path, params: subscription_params }

    assert_equal 1, PushSubscription.where(endpoint: "https://push.example/abc").count
  end

  test "removes a subscription by endpoint" do
    @user.push_subscriptions.create!(endpoint: "https://push.example/abc", p256dh_key: "p", auth_key: "a")

    assert_difference "PushSubscription.count", -1 do
      delete push_subscriptions_path, params: { endpoint: "https://push.example/abc" }
    end

    assert_response :no_content
  end

  private

  def subscription_params
    { push_subscription: { endpoint: "https://push.example/abc", p256dh_key: "p", auth_key: "a" } }
  end
end
