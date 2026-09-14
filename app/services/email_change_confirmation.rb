# Finishes a change of address. The token is the proof, so this runs without a
# session — the link is opened in an email client, which may not carry one.
#
# Confirming an address also verifies the account: the person just proved they
# receive mail there, which is the whole question email confirmation asks.
class EmailChangeConfirmation
  Result = Data.define(:user, :error) do
    def success? = error.nil?
  end

  def initialize(token)
    @token = token
  end

  def call
    user = User.find_by_token_for(:email_change, token)
    return Result.new(user: nil, error: :expired) if user.nil? || !user.email_change_pending?

    user.update!(
      email_address: user.pending_email_address,
      pending_email_address: nil,
      verified_at: Time.current
    )
    Result.new(user: user, error: nil)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Somebody registered the address between the request and the click. The
    # unique index is the thing that decides, and it just did.
    #
    # Reloaded first: the failed save left the in-memory record holding the
    # address that was just rejected, so saving it again — even to clear the
    # request — fails the same way and leaves a pending change that can never be
    # confirmed and never goes away.
    user.reload.update!(pending_email_address: nil)
    Result.new(user: user, error: :taken)
  end

  private

  attr_reader :token
end
