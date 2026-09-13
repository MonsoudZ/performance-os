require "application_system_test_case"

# The push toggle is the only JavaScript that writes to the database, and what it
# writes is an endpoint the server later makes an outbound request to. That makes
# it worth a browser test twice over: the controller's own logic, and the fact
# that what the browser hands us survives the SSRF allow-list on the other side.
#
# A real push subscription needs a vendor push service, which no test can reach,
# so the three browser APIs the controller reads are stubbed. Everything below
# the stub — the fetch, the controller, the validation, the row — is real.
class PushRemindersTest < ApplicationSystemTestCase
  VENDOR_ENDPOINT = "https://fcm.googleapis.com/fcm/send/system-test-token".freeze

  setup do
    @user = users(:one)
    # The panel stays hidden without a VAPID key, which is how production behaves
    # when push is not configured.
    @vapid = Rails.application.config.x.vapid
    Rails.application.config.x.vapid = @vapid.merge(
      public_key: "BExampleVapidPublicKeyForSystemTests_1234567890abcdefghijklmnop"
    )
  end

  teardown { Rails.application.config.x.vapid = @vapid }

  test "subscribing stores the endpoint the browser reported" do
    stub_push_api
    sign_in @user

    assert_selector ".push-toggle", text: "Enable check-in reminders", wait: 5

    assert_difference -> { @user.push_subscriptions.count }, 1 do
      click_on "Enable check-in reminders"
      assert_selector ".push-toggle", text: "Disable check-in reminders", wait: 5
    end

    subscription = @user.push_subscriptions.order(:id).last

    assert_equal VENDOR_ENDPOINT, subscription.endpoint
    assert_equal "test-p256dh", subscription.p256dh_key
    assert_equal "test-auth", subscription.auth_key
  end

  test "unsubscribing removes the row again" do
    stub_push_api(subscribed: true)
    @user.push_subscriptions.create!(
      endpoint: VENDOR_ENDPOINT, p256dh_key: "test-p256dh", auth_key: "test-auth"
    )
    sign_in @user

    assert_selector ".push-toggle", text: "Disable check-in reminders", wait: 5

    assert_difference -> { @user.push_subscriptions.count }, -1 do
      click_on "Disable check-in reminders"
      assert_selector ".push-toggle", text: "Enable check-in reminders", wait: 5
    end
  end

  test "a denied permission prompt leaves nothing behind" do
    stub_push_api(permission: "denied")
    sign_in @user

    assert_selector ".push-toggle", text: "Enable check-in reminders", wait: 5

    assert_no_difference -> { @user.push_subscriptions.count } do
      click_on "Enable check-in reminders"
      # The label is the only signal the user gets, and it must not claim success.
      assert_no_selector ".push-toggle", text: "Disable check-in reminders", wait: 2
    end
  end

  test "the toggle stays hidden when push is not configured" do
    Rails.application.config.x.vapid = @vapid.merge(public_key: nil)
    stub_push_api
    sign_in @user

    assert_selector ".check-in", wait: 5
    assert_no_selector ".push-toggle", visible: true
  end

  test "the toggle stays hidden in a browser without push support" do
    stub_browser_api("delete window.PushManager;")
    sign_in @user

    assert_selector ".check-in", wait: 5
    assert_no_selector ".push-toggle", visible: true
  end

  private

  # Stands in for serviceWorker.ready, PushManager and Notification. Chrome
  # headless has no push service, so pushManager.subscribe would never resolve.
  def stub_push_api(subscribed: false, permission: "granted")
    stub_browser_api(<<~JS)
      (() => {
        const endpoint = #{VENDOR_ENDPOINT.to_json};
        let current = #{subscribed ? "makeSubscription()" : "null"};

        function makeSubscription() {
          return {
            endpoint,
            toJSON: () => ({ keys: { p256dh: "test-p256dh", auth: "test-auth" } }),
            unsubscribe: async () => { current = null; return true; }
          };
        }

        const registration = {
          pushManager: {
            getSubscription: async () => current,
            subscribe: async () => { current = makeSubscription(); return current; }
          }
        };

        Object.defineProperty(navigator, "serviceWorker", {
          configurable: true,
          value: { ready: Promise.resolve(registration), register: async () => registration }
        });

        window.PushManager = function PushManager() {};
        window.Notification = { requestPermission: async () => #{permission.to_json} };
      })();
    JS
  end
end
