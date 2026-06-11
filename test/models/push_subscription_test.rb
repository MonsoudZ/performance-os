require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "requires endpoint and keys" do
    subscription = PushSubscription.new(user: @user)
    assert_not subscription.valid?
    assert_includes subscription.errors.attribute_names, :endpoint
    assert_includes subscription.errors.attribute_names, :p256dh_key
    assert_includes subscription.errors.attribute_names, :auth_key
  end

  test "endpoint is unique" do
    @user.push_subscriptions.create!(endpoint: "https://push.example/a", p256dh_key: "p", auth_key: "a")
    dup = users(:two).push_subscriptions.build(endpoint: "https://push.example/a", p256dh_key: "p", auth_key: "a")

    assert_not dup.valid?
  end
end
