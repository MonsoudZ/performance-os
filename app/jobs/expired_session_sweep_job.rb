# Deletes sessions that have already stopped working.
#
# Expiry is enforced on the way in, so this changes nothing about what a request
# can do — it exists because a user who never comes back never makes that
# request, and their dead rows would otherwise sit in the table forever.
class ExpiredSessionSweepJob < ApplicationJob
  queue_as :default

  def perform
    swept = Session.expired.delete_all
    Rails.logger.info("ExpiredSessionSweepJob swept #{swept} expired #{'session'.pluralize(swept)}") if swept.positive?
    swept
  end
end
