# VAPID keys for Web Push. Generate a pair with `WebPush.generate_key` and set
# VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY (and optionally VAPID_SUBJECT) in the
# environment. Without them, push delivery is a no-op.
Rails.application.config.x.vapid = {
  public_key: ENV["VAPID_PUBLIC_KEY"],
  private_key: ENV["VAPID_PRIVATE_KEY"],
  subject: ENV.fetch("VAPID_SUBJECT", "mailto:support@performance-os.app")
}
