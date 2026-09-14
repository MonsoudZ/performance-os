# Failures used to go to STDOUT and, for a job that had given up, into
# solid_queue_failed_executions — where a user's plan quietly not updating looks
# the same as nothing happening. Rails already routes unhandled request errors
# and exhausted jobs to Rails.error; this is the thing on the other end.
#
# Recording is unconditional and needs no configuration. Notifying needs
# ERROR_REPORT_TO and deliverable mail, and production says so at boot rather
# than looking configured and being silent — the same failure mode the SMTP
# scaffold had.
Rails.application.configure do
  config.after_initialize do
    Rails.error.subscribe(ErrorReporter.new)

    next unless Rails.env.production?
    next if ErrorReporter.notifying?

    Rails.logger.warn(
      "Error alerts are not configured (#{ErrorReporter.to_address.blank? ? 'ERROR_REPORT_TO unset' : 'mail undeliverable'}): " \
      "failures are still recorded in error_reports and the log, but nobody is told about them."
    )
  end
end
