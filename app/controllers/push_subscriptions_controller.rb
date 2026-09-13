class PushSubscriptionsController < ApplicationController
  def create
    subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    subscription.assign_attributes(
      user: Current.user,
      p256dh_key: subscription_params[:p256dh_key],
      auth_key: subscription_params[:auth_key]
    )
    if subscription.save
      head :created
    else
      # A rejected endpoint is a bad request, not a server error: the browser
      # supplied it, so let it see that rather than raising.
      render json: { errors: subscription.errors.full_messages }, status: :unprocessable_entity
    end
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
