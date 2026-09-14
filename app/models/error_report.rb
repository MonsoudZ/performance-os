class ErrorReport < ApplicationRecord
  SEVERITIES = %w[error warning info].freeze

  # How long a distinct failure stays quiet after somebody has been told about
  # it. Without this, one error hitting every user in a recompute sweep is a
  # mailbox full of the same sentence — and the second copy tells you nothing
  # the first did not.
  NOTIFY_INTERVAL = 1.hour

  # Enough to identify the failure; not so much that the row becomes a place
  # health data accumulates. The message can still quote values from a failing
  # query, so this table carries the same sensitivity as the data it is about.
  MESSAGE_LIMIT = 1_000
  BACKTRACE_LINES = 20

  validates :fingerprint, :error_class, presence: true
  validates :fingerprint, uniqueness: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :occurrences, numericality: { greater_than: 0 }

  scope :recent_first, -> { order(last_seen_at: :desc) }
  scope :unnotified, -> { where(last_notified_at: nil) }

  # Distinct failures are (class, where it was raised). The top frame from this
  # app is used rather than the whole backtrace, so the same bug reported from
  # two different requests is one row, while two different bugs of the same class
  # stay apart.
  def self.fingerprint_for(error, source)
    frame = Array(error.backtrace).find { |line| line.start_with?(Rails.root.to_s) }
    Digest::SHA256.hexdigest([ error.class.name, source, frame ].join("\n"))[0, 32]
  end

  # Upserted rather than inserted: the second occurrence of a failure is a
  # counter, not a new thing to look at. Returns the row so the caller can decide
  # whether anybody needs telling.
  def self.record!(error, source:, severity:, handled:, context:, now: Time.current)
    fingerprint = fingerprint_for(error, source)

    transaction do
      report = lock.find_by(fingerprint: fingerprint)

      if report
        report.update!(
          message: truncated_message(error),
          backtrace: truncated_backtrace(error),
          context: context,
          occurrences: report.occurrences + 1,
          last_seen_at: now
        )
        report
      else
        create!(
          fingerprint: fingerprint,
          error_class: error.class.name,
          message: truncated_message(error),
          backtrace: truncated_backtrace(error),
          source: source,
          severity: severity,
          handled: handled,
          context: context,
          occurrences: 1,
          first_seen_at: now,
          last_seen_at: now
        )
      end
    end
  end

  def self.truncated_message(error) = error.message.to_s.truncate(MESSAGE_LIMIT)

  def self.truncated_backtrace(error)
    Array(error.backtrace).first(BACKTRACE_LINES).join("\n").presence
  end

  # An error the app caught and carried on from is worth recording and not worth
  # waking somebody for.
  def notifiable?(now: Time.current)
    return false if handled?
    return true if last_notified_at.nil?

    last_notified_at <= now - NOTIFY_INTERVAL
  end

  def new_failure? = occurrences == 1
end
