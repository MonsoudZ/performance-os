require "test_helper"

class WearableDevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "pairs a device and returns a one-time bearer token" do
    assert_difference "WearableDevice.count", 1 do
      post wearable_devices_path, params: {
        wearable_device: {
          platform: "ios_healthkit",
          external_id: "installation-123",
          name: "Mon’s iPhone"
        }
      }, as: :json
    end

    assert_response :created
    body = response.parsed_body
    device = @user.wearable_devices.last

    assert_match(/\A#{device.id}\./, body.fetch("access_token"))
    assert_not_equal body.fetch("access_token"), device.token_digest
    assert_equal api_v1_wearable_sync_url, body.fetch("sync_url")
  end

  test "re-pairing rotates the token without creating another device" do
    device, first_token = WearableDevice.issue_for!(
      user: @user,
      platform: "ios_healthkit",
      external_id: "installation-123",
      name: "Mon’s iPhone"
    )

    assert_no_difference "WearableDevice.count" do
      post wearable_devices_path, params: {
        wearable_device: {
          platform: "ios_healthkit",
          external_id: "installation-123",
          name: "Mon’s iPhone"
        }
      }, as: :json
    end

    assert_not device.reload.authenticate_token(first_token.split(".", 2).last)
    assert device.authenticate_token(response.parsed_body.fetch("access_token").split(".", 2).last)
  end

  test "lists the user's paired devices" do
    WearableDevice.issue_for!(user: @user, platform: "ios_healthkit", external_id: "phone-a", name: "iPhone")
    foreign, = WearableDevice.issue_for!(user: users(:two), platform: "ios_healthkit", external_id: "phone-b", name: "Other phone")

    get wearable_devices_path

    assert_response :success
    assert_select "strong", text: "iPhone"
    assert_select "strong", text: foreign.name, count: 0
  end
end
