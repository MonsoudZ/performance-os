# Starts a change of address. Nothing moves until the new address is confirmed:
# the request is parked in `pending_email_address` and the account keeps working
# on the address it has.
#
# That ordering is the whole design. Writing the new address straight in would
# mean a typo costs every route back into the account — a password reset would
# be sent somewhere that does not exist — and would let anyone holding a session
# take the account outright, since the owner would stop receiving anything.
#
# Two things guard against the session-holder case: the current password is
# required, the same bar account deletion sets, and the *old* address is told
# that a change was asked for. The second matters more, because it is the one
# that reaches the real owner.
class EmailChangeRequest
  Result = Data.define(:user, :error) do
    def success? = error.nil?
  end

  def initialize(user, new_address:, password:)
    @user = user
    @new_address = new_address.to_s.strip.downcase.presence
    @password = password.to_s
  end

  def call
    error = validation_error
    return Result.new(user: user, error: error) if error

    user.update!(pending_email_address: new_address)
    EmailChangesMailer.confirm(user).deliver_later
    # To the address being left, not the one being requested: this is the
    # message that reaches the owner if somebody else started the change.
    EmailChangesMailer.notify_previous(user, new_address).deliver_later

    Result.new(user: user, error: nil)
  end

  private

  attr_reader :user, :new_address, :password

  def validation_error
    # Fails closed, unlike confirmation of a new account. Starting a change that
    # can never be confirmed leaves a request hanging forever; refusing to start
    # one leaves the account exactly as it was, which is the safer of the two.
    return "Email is not configured, so an address cannot be confirmed right now." unless EmailChangesMailer.enforced?
    return "Enter the new email address." if new_address.blank?
    return "That is already your email address." if new_address == user.email_address
    return "That password is not right, so nothing was changed." unless user.authenticate(password)
    return "That email address is already in use." if taken?

    nil
  end

  # Checked again at confirmation time, because somebody else can register it in
  # between — the unique index is what finally decides.
  def taken?
    User.where.not(id: user.id).exists?(email_address: new_address)
  end
end
