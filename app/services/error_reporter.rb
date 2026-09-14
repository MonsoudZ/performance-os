# What happens when something fails.
#
# Rails already routes unhandled request errors and jobs that have given up to
# `Rails.error` — a job that exhausts ApplicationJob's five retries reports once,
# at the attempt it stops on, and the retries in between stay quiet. What was
# missing is anything on the other end: failures went to STDOUT and into
# `solid_queue_failed_executions`, where a user's plan silently stopping updating
# looks exactly like nothing happening.
#
# Recording always, notifying sometimes: the log is the record, the email is the
# interruption, and only one of those should scale with how often an error fires.
class ErrorReporter
  def self.to_address = ENV["ERROR_REPORT_TO"].presence

  # Mail has to be deliverable as well as addressed — the same question the
  # confirmation gate asks, for the same reason. An alert nobody can receive is
  # not a control, and pretending otherwise hides the failure it is about.
  def self.notifying? = to_address.present? && ActionMailer::Base.perform_deliveries

  def report(error, handled:, severity:, context: {}, source: nil)
    attributes = {
      source: source.to_s.presence,
      severity: SEVERITIES.fetch(severity, "error"),
      handled: handled,
      context: sanitized_context(context)
    }

    log(error, attributes)
    report = ErrorReport.record!(error, **attributes)
    notify(report) if report.notifiable?
  rescue StandardError => e
    # The reporter failing must never become the error. If the database is what
    # broke, recording an error about it there will break the same way, and
    # raising here would replace a useful exception with a useless one.
    Rails.logger.error("ErrorReporter could not record #{error.class}: #{e.class} #{e.message}")
  end

  SEVERITIES = { error: "error", warning: "warning", info: "info" }.freeze

  private

  def log(error, attributes)
    Rails.logger.error(
      "[#{attributes[:severity]}] #{error.class}: #{error.message} " \
      "(source=#{attributes[:source] || 'none'} handled=#{attributes[:handled]} " \
      "context=#{attributes[:context].to_json})"
    )
  end

  # Only what is useful for finding the failure again, never what was being
  # worked on: no params, no headers, no addresses. The user is an id, so an
  # error outliving an account leaves an integer rather than anything about them.
  def sanitized_context(context)
    job = context[:job]

    {
      "job" => job&.class&.name,
      "job_id" => job&.job_id,
      "attempt" => job&.executions,
      "user_id" => user_id_from(context, job)
    }.compact
  end

  def user_id_from(context, job)
    return context[:user_id] if context[:user_id]

    argument = Array(job&.arguments).find { |value| value.is_a?(User) }
    argument&.id
  end

  def notify(report)
    return unless self.class.notifying?

    ErrorReportsMailer.alert(report).deliver_later
    report.update_column(:last_notified_at, Time.current)
  rescue StandardError => e
    # Same rule as above: an alert that cannot be sent is logged, not raised.
    # If it is the delivery job itself that keeps failing, that failure is
    # reported like any other and NOTIFY_INTERVAL is what stops the two feeding
    # each other — the second round finds the same fingerprint and goes quiet.
    Rails.logger.error("ErrorReporter could not notify about ##{report.id}: #{e.class} #{e.message}")
  end
end
