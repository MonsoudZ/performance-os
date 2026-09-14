class EmailVerificationsMailer < ApplicationMailer
  # Whether confirmation is a requirement or a suggestion, mirroring
  # CoachNarrator.configured?: a feature that leans on an outside service asks
  # whether that service is actually there.
  #
  # If mail cannot be delivered then nobody can confirm, and enforcing it would
  # not be security — it would be an outage nobody could clear. Production says
  # so at boot (config/initializers/mail.rb) rather than failing open in silence.
  def self.enforced?
    ActionMailer::Base.perform_deliveries
  end

  def verify(user)
    @user = user
    mail subject: "Confirm your email address", to: user.email_address
  end
end
