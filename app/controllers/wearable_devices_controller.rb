class WearableDevicesController < ApplicationController
  def create
    device, access_token = WearableDevice.issue_for!(
      user: Current.user,
      platform: wearable_device_params.fetch(:platform),
      external_id: wearable_device_params.fetch(:external_id),
      name: wearable_device_params.fetch(:name)
    )

    render json: {
      device: {
        id: device.id,
        platform: device.platform,
        name: device.name
      },
      access_token: access_token,
      sync_url: api_v1_wearable_sync_url
    }, status: :created
  end

  def destroy
    device = Current.user.wearable_devices.find(params[:id])
    device.update!(revoked_at: Time.current)
    redirect_to root_path, notice: "Wearable access revoked."
  end

  private

  def wearable_device_params
    params.require(:wearable_device).permit(:platform, :external_id, :name)
  end
end
