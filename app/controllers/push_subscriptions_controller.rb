class PushSubscriptionsController < ApplicationController
  def create
    subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    subscription.assign_attributes(
      user: Current.user,
      p256dh_key: subscription_params[:p256dh_key],
      auth_key: subscription_params[:auth_key]
    )
    subscription.save!
    head :created
  end

  def destroy
    Current.user.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all
    head :no_content
  end

  private

  def subscription_params
    params.require(:push_subscription).permit(:endpoint, :p256dh_key, :auth_key)
  end
end
