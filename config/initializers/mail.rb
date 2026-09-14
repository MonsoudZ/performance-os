# Mail is load-bearing: a password reset and an email confirmation are both
# delivered by it, and an account that cannot receive either is an account
# nobody can recover.
#
# Rails ships production defaults that look configured and are not — an SMTP
# block commented out, and a host of "example.com" baked into every link. Both
# fail silently, which is the worst way for this to fail, so production says so
# at boot instead.
Rails.application.configure do
  next unless Rails.env.production?

  config.after_initialize do
    missing = []
    missing << "APP_HOST" if ENV["APP_HOST"].blank?
    missing << "SMTP_ADDRESS" if ENV["SMTP_ADDRESS"].blank?
    next if missing.empty?

    Rails.logger.warn(
      "Mail is not configured (#{missing.join(', ')} unset): password resets and " \
      "email confirmations will not be delivered. Confirmation is not enforced " \
      "while this is true, so nobody is locked out by it."
    )
  end
end
