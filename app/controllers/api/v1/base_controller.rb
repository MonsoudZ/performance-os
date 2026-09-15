module Api
  module V1
    # What every authenticated native endpoint inherits.
    #
    # The bearer token names a `Session` row, so the phone is a signed-in device
    # like any other: it shows up in the user's list at /profile/edit, it is
    # ended from there, and it dies on the same two clocks as a browser session.
    #
    # `Current.session` is set for the duration of the request so anything the
    # web app already reads through `Current.user` — evaluators, services,
    # recompute helpers — works unchanged from here.
    class BaseController < ActionController::API
      before_action :authenticate_session!

      private

      def authenticate_session!
        session = Session.authenticate_api_token(bearer_token)
        return unauthorized unless session

        session.touch_activity
        Current.session = session
      end

      def bearer_token
        request.authorization&.delete_prefix("Bearer ")
      end

      def unauthorized
        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def current_user
        Current.user
      end

      # A native client gets the same answer for a missing record as the web
      # does for another account's: not found, with nothing said about whether
      # it exists and belongs to somebody else.
      def not_found
        render json: { error: "Not found" }, status: :not_found
      end

      def rescue_from_missing
        yield
      rescue ActiveRecord::RecordNotFound
        not_found
      end
    end
  end
end
