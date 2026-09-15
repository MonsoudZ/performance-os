# The device itself, so a client can show "signed in as this phone since…" and
# tell the user when it will have to sign in again.
#
# `expires_at` is derived rather than stored: the session's two clocks decide,
# and whichever runs out first is the one that ends it.
class SessionSerializer
  def initialize(session)
    @session = session
  end

  def as_json(*)
    {
      id: session.id,
      device_label: session.device_label,
      created_at: session.created_at.iso8601,
      last_active_at: session.last_active_at.iso8601,
      expires_at: expires_at.iso8601
    }
  end

  private

  attr_reader :session

  def expires_at
    [
      session.last_active_at + Session::IDLE_TIMEOUT,
      session.created_at + Session::ABSOLUTE_LIFETIME
    ].min
  end
end
