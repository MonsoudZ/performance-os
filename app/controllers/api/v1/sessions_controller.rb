module Api
  module V1
    # Signing a phone in and out.
    #
    # Creating one makes a real `Session` row, so the device is listed at
    # /profile/edit with the others and can be ended from there. Deleting one
    # destroys the row rather than blanking the digest — a revoked session is
    # over, and leaving it behind would show a live device that is not.
    class SessionsController < BaseController
      allow_unauthenticated = %i[create]
      skip_before_action :authenticate_session!, only: allow_unauthenticated

      def create
        user = User.authenticate_by(email_address: params[:email_address].to_s, password: params[:password].to_s)
        return render(json: { error: "Invalid email or password" }, status: :unauthorized) unless user

        session = user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)

        render json: {
          # Shown once. Only the digest is kept, so a client that loses this
          # signs in again rather than asking for it back.
          token: session.issue_api_token!,
          session: SessionSerializer.new(session).as_json,
          user: UserSerializer.new(user).as_json
        }, status: :created
      end

      def destroy
        Current.session.destroy!
        head :no_content
      end
    end
  end
end
