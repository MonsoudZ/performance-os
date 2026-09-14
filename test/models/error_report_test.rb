require "test_helper"

class ErrorReportTest < ActiveSupport::TestCase
  test "the same failure from two places is one row with a count" do
    first = ErrorReport.record!(raised("boom"), **attributes)
    second = ErrorReport.record!(raised("boom"), **attributes)

    assert_equal first.id, second.id
    assert_equal 2, second.reload.occurrences
    assert_not second.new_failure?
  end

  # Two different bugs of the same class must not collapse into one row, or the
  # second one is invisible behind the first one's count.
  test "the same class raised from different lines are different rows" do
    here = ErrorReport.record!(raised("boom"), **attributes)
    there = ErrorReport.record!(raised_elsewhere("boom"), **attributes)

    assert_not_equal here.fingerprint, there.fingerprint
  end

  test "different classes from the same line are different rows" do
    argument = ErrorReport.record!(raised("boom"), **attributes)
    type = ErrorReport.record!(raised("boom", TypeError), **attributes)

    assert_not_equal argument.fingerprint, type.fingerprint
  end

  test "first and last seen bracket the occurrences" do
    earlier = 2.hours.ago
    ErrorReport.record!(raised("boom"), **attributes, now: earlier)
    report = ErrorReport.record!(raised("boom"), **attributes, now: Time.current)

    assert_in_delta earlier, report.first_seen_at, 1
    assert_operator report.last_seen_at, :>, report.first_seen_at
  end

  # A message can quote values from the failing query, so it is capped rather
  # than allowed to grow into a place data accumulates.
  test "an enormous message is truncated" do
    report = ErrorReport.record!(raised("x" * 5_000), **attributes)

    assert_operator report.message.length, :<=, ErrorReport::MESSAGE_LIMIT
  end

  test "a backtrace is capped to the frames that identify the failure" do
    report = ErrorReport.record!(raised("boom"), **attributes)

    assert_operator report.backtrace.lines.size, :<=, ErrorReport::BACKTRACE_LINES
  end

  test "an unnotified failure is notifiable and a just-notified one is not" do
    report = ErrorReport.record!(raised("boom"), **attributes)

    assert report.notifiable?

    report.update!(last_notified_at: Time.current)
    assert_not report.notifiable?

    report.update!(last_notified_at: ErrorReport::NOTIFY_INTERVAL.ago - 1.minute)
    assert report.notifiable?, "a failure still firing after the interval is worth saying again"
  end

  # An error the app caught and carried on from is worth recording and not worth
  # waking somebody for.
  test "a handled error is never notifiable" do
    report = ErrorReport.record!(raised("boom"), **attributes, handled: true, severity: "warning")

    assert_not report.notifiable?
  end

  private

  def attributes(handled: false, severity: "error")
    { source: "application.active_support", severity: severity, handled: handled, context: { "job" => "X" } }
  end

  def raised(message, klass = ArgumentError)
    raise klass, message
  rescue StandardError => e
    e
  end

  def raised_elsewhere(message)
    raise ArgumentError, message
  rescue StandardError => e
    e
  end
end
