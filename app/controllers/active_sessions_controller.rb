# Where a user is signed in, and how they stop being signed in there.
#
# Scoped to `Current.user.sessions` throughout, so a session id belonging to
# somebody else is a 404 rather than a revocation.
class ActiveSessionsController < ApplicationController
  def destroy
    session = Current.user.sessions.find(params[:id])
    current = session == Current.session
    session.destroy

    if current
      # Signing yourself out from the list is still signing out.
      cookies.delete(:session_id)
      Current.session = nil
      redirect_to new_session_path, status: :see_other, notice: "Signed out on this device."
    else
      redirect_to edit_profile_path, status: :see_other, notice: "Signed out on that device."
    end
  end

  # The answer to "something is in that list that I do not recognize", so it
  # takes everything but the device asking — a user who has to revoke one at a
  # time gets it wrong under exactly the pressure that makes them use it.
  def destroy_others
    revoked = Current.user.sessions.where.not(id: Current.session.id).destroy_all.size

    redirect_to edit_profile_path, status: :see_other,
      notice: revoked.zero? ?
        "This is the only device you're signed in on." :
        "Signed out on #{ActionController::Base.helpers.pluralize(revoked, 'other device')}."
  end
end
