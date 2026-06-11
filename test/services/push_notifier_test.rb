require "test_helper"

class PushNotifierTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @subscription = @user.push_subscriptions.create!(endpoint: "https://push.example/abc", p256dh_key: "p", auth_key: "a")
    @original_vapid = Rails.application.config.x.vapid
  end

  teardown { Rails.application.config.x.vapid = @original_vapid }

  test "is a no-op when VAPID keys are absent" do
    Rails.application.config.x.vapid = { public_key: nil, private_key: nil, subject: "mailto:x@y.z" }

    assert_not PushNotifier.deliver(@subscription, title: "Hi", body: "Yo")
  end

  test "sends the built message via WebPush when configured" do
    configure_vapid
    captured = nil

    swap_webpush(->(**kwargs) { captured = kwargs }) do
      assert PushNotifier.deliver(@subscription, title: "Time to check in", body: "Log recovery", path: "/")
    end

    assert_equal @subscription.endpoint, captured[:endpoint]
    assert_includes captured[:message], "Time to check in"
  end

  test "deletes a subscription the push service reports as gone" do
    configure_vapid
    response = Struct.new(:code, :message, :body).new("410", "Gone", "")

    swap_webpush(->(**) { raise WebPush::ExpiredSubscription.new(response, "push.example") }) do
      assert_not PushNotifier.deliver(@subscription, title: "Hi", body: "Yo")
    end

    assert_not PushSubscription.exists?(@subscription.id)
  end

  private

  def configure_vapid
    Rails.application.config.x.vapid = { public_key: "pub", private_key: "priv", subject: "mailto:x@y.z" }
  end

  def swap_webpush(handler)
    original = WebPush.method(:payload_send)
    WebPush.define_singleton_method(:payload_send) { |**kwargs| handler.call(**kwargs) }
    yield
  ensure
    WebPush.define_singleton_method(:payload_send, original)
  end
end
