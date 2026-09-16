class ApplicationController < ActionController::Base
  include Authentication
  include UserTimeZone
  around_action :resume_session_in_user_time_zone
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # The session has to be resumed before the zone can be read off the user, so
  # this is one callback rather than two: an `around_action` wrapping a
  # `before_action` would read the clock before anyone was signed in.
  def resume_session_in_user_time_zone(&action)
    resume_session
    use_user_time_zone(&action)
  end
end
