class ErrorReportsMailer < ApplicationMailer
  # Goes to whoever runs the app, not to a user, so it says what broke and where
  # rather than apologising. Sent at most once an hour per distinct failure —
  # see ErrorReport::NOTIFY_INTERVAL.
  def alert(report)
    @report = report

    mail(
      to: ErrorReporter.to_address,
      subject: "[PerformanceOS] #{report.new_failure? ? '' : "#{report.occurrences}× "}#{report.error_class}"
    )
  end
end
