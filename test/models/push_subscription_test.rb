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
    @user.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/a", p256dh_key: "p", auth_key: "a")
    dup = users(:two).push_subscriptions.build(endpoint: "https://fcm.googleapis.com/fcm/send/a", p256dh_key: "p", auth_key: "a")

    assert_not dup.valid?
  end
  # The reminder job POSTs to this URL from the server on a schedule, so an
  # unchecked endpoint is a server-side request forgery any signed-in user can
  # arm. These are the addresses that matter if the check ever regresses.
  test "rejects endpoints that are not a vendor push service" do
    [
      "http://169.254.169.254/latest/meta-data/",
      "https://169.254.169.254/latest/meta-data/",
      "http://localhost:3000/admin",
      "https://127.0.0.1/internal",
      "https://10.0.0.5/internal",
      "https://attacker.example/collect",
      "https://fcm.googleapis.com.attacker.example/collect",
      "https://notfcm.googleapis.com/fcm/send/abc",
      "file:///etc/passwd",
      "not a url at all"
    ].each do |endpoint|
      subscription = @user.push_subscriptions.build(endpoint:, p256dh_key: "p", auth_key: "a")

      assert_not subscription.valid?, "#{endpoint} should be rejected"
      assert_includes subscription.errors.attribute_names, :endpoint
    end
  end

  test "accepts the real vendor push services over https" do
    [
      "https://fcm.googleapis.com/fcm/send/abc",
      "https://updates.push.services.mozilla.com/wpush/v2/abc",
      "https://web.push.apple.com/abc",
      "https://par02p.notify.windows.com/w/?token=abc",
      "https://fcm.googleapis.com./fcm/send/abc"
    ].each_with_index do |endpoint, index|
      subscription = @user.push_subscriptions.build(endpoint:, p256dh_key: "p#{index}", auth_key: "a#{index}")

      assert subscription.valid?, "#{endpoint} should be accepted: #{subscription.errors.full_messages}"
    end
  end

  test "http is rejected even on an allowed host" do
    subscription = @user.push_subscriptions.build(
      endpoint: "http://fcm.googleapis.com/fcm/send/abc", p256dh_key: "p", auth_key: "a"
    )

    assert_not subscription.valid?
  end

  test "an operator can allow an additional provider without a deploy" do
    endpoint = "https://push.newvendor.example/abc"

    assert_not @user.push_subscriptions.build(endpoint:, p256dh_key: "p", auth_key: "a").valid?

    ENV["WEB_PUSH_ALLOWED_HOSTS"] = "push.newvendor.example"
    begin
      assert @user.push_subscriptions.build(endpoint:, p256dh_key: "p", auth_key: "a").valid?
    ensure
      ENV.delete("WEB_PUSH_ALLOWED_HOSTS")
    end
  end
end
