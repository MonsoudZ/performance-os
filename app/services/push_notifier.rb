class PushNotifier
  # Sends one Web Push message to a subscription. Returns true on success. A
  # subscription the push service reports as gone is deleted; other errors are
  # logged so one bad endpoint can't break a batch.
  def self.deliver(subscription, title:, body:, path: "/")
    vapid = Rails.application.config.x.vapid
    return false if vapid[:public_key].blank? || vapid[:private_key].blank?

    WebPush.payload_send(
      message: JSON.generate(title: title, options: { body: body, data: { path: path } }),
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh_key,
      auth: subscription.auth_key,
      vapid: { subject: vapid[:subject], public_key: vapid[:public_key], private_key: vapid[:private_key] },
      urgency: "normal"
    )
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    subscription.destroy
    false
  rescue WebPush::ResponseError => error
    Rails.logger.warn("PushNotifier failed for subscription #{subscription.id}: #{error.message}")
    false
  end
end
