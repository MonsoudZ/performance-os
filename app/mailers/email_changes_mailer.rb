class EmailChangesMailer < ApplicationMailer
  # Same question EmailVerificationsMailer asks, and the same answer: a flow
  # built on a link nobody receives is not a flow.
  def self.enforced?
    ActionMailer::Base.perform_deliveries
  end

  # To the address being requested. Only this one carries the link.
  def confirm(user)
    @user = user
    mail subject: "Confirm your new email address", to: user.pending_email_address
  end

  # To the address being left. Carries no link and asks for no action, because
  # its only job is to reach the real owner if somebody else started this.
  def notify_previous(user, new_address)
    @user = user
    @new_address = new_address
    mail subject: "Someone asked to change your email address", to: user.email_address
  end
end
