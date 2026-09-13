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
    assert_equal @user, PushSubscription.find_by(endpoint: "https://fcm.googleapis.com/fcm/send/abc").user
  end

  test "is idempotent on the same endpoint" do
    2.times { post push_subscriptions_path, params: subscription_params }

    assert_equal 1, PushSubscription.where(endpoint: "https://fcm.googleapis.com/fcm/send/abc").count
  end

  test "removes a subscription by endpoint" do
    @user.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/abc", p256dh_key: "p", auth_key: "a")

    assert_difference "PushSubscription.count", -1 do
      delete push_subscriptions_path, params: { endpoint: "https://fcm.googleapis.com/fcm/send/abc" }
    end

    assert_response :no_content
  end

  test "refuses to store an endpoint that is not a push service" do
    assert_no_difference "PushSubscription.count" do
      post push_subscriptions_path, params: {
        push_subscription: {
          endpoint: "http://169.254.169.254/latest/meta-data/", p256dh_key: "p", auth_key: "a"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  private

  def subscription_params
    { push_subscription: { endpoint: "https://fcm.googleapis.com/fcm/send/abc", p256dh_key: "p", auth_key: "a" } }
  end
end
