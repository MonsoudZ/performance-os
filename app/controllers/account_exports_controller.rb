class AccountExportsController < ApplicationController
  # Generated inline rather than queued, because there is nowhere to put a file:
  # no object storage is configured. A few years of training serializes into
  # single-digit megabytes, which a request can carry — but the whole document is
  # built in memory, and the fat part is coaching decisions, one per lift per
  # session with its evidence snapshot. An account heavy enough to feel that is
  # the signal to move this to a job and somewhere to store the result.
  #
  # The rate limit matters more than for any page: this reads every table the
  # account touches.
  rate_limit to: 5, within: 1.hour,
    with: -> { redirect_to edit_profile_path, alert: "That is a lot of exports. Try again in a little while." }

  def show
    export = AccountExport.new(Current.user)

    send_data export.to_json,
      filename: export.filename,
      type: "application/json",
      disposition: "attachment"
  end
end
