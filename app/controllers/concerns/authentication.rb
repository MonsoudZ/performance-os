module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # A session now has a clock. An expired one is cleared rather than merely
    # ignored, so the row does not sit there looking live in the user's list of
    # signed-in devices, and the cookie stops being sent.
    def find_session_by_cookie
      return unless cookies.signed[:session_id]

      session = Session.find_by(id: cookies.signed[:session_id])
      return if session.nil?
      return discard(session) if session.expired?

      session.touch_activity
      session
    end

    # Deleted, not just ignored: an expired session is over, and leaving the row
    # behind would show it as a live device in the user's list until the daily
    # sweep got to it.
    def discard(session)
      session.destroy
      cookies.delete(:session_id)
      nil
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        # Expires with the session it names rather than in twenty years, so a
        # cookie the server would refuse is not kept and sent anyway. The
        # server-side check is still the one that decides.
        cookies.signed[:session_id] = {
          value: session.id,
          httponly: true,
          same_site: :lax,
          expires: Session::ABSOLUTE_LIFETIME.from_now
        }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
