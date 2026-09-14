class ApplicationMailer < ActionMailer::Base
  # The scaffold's literal "from@example.com", like the commented-out SMTP block
  # beside it, looks configured and is not: most providers reject or filter it,
  # so every password reset and error alert leaves looking like spam. Derived
  # from APP_HOST, which mail already cannot work without, so setting that one
  # variable is still the whole requirement.
  default from: ENV.fetch("MAIL_FROM") { "no-reply@#{ENV.fetch('APP_HOST', 'localhost')}" }
  layout "mailer"
end
