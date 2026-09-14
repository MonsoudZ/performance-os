class ApplicationJob < ActiveJob::Base
  # Transient database contention, not bugs. Every job under here recomputes
  # derived state through evaluators that are contractually idempotent — the
  # pipeline re-runs them freely and they short-circuit when nothing moved — so
  # running one again is free, and the alternative is a user whose plan silently
  # stops updating because of one deadlock.
  #
  # Deliberately narrow: a StatementInvalid is usually a bug, and retrying one
  # five times only delays finding it.
  RETRYABLE_DATABASE_ERRORS = [
    ActiveRecord::Deadlocked,
    ActiveRecord::LockWaitTimeout,
    ActiveRecord::SerializationFailure,
    # Covers ConnectionFailed, which subclasses it: a database restart or a
    # failover, where waiting is exactly the right response.
    ActiveRecord::ConnectionNotEstablished
  ].freeze

  RETRY_ATTEMPTS = 5

  retry_on(*RETRYABLE_DATABASE_ERRORS, wait: :polynomially_longer, attempts: RETRY_ATTEMPTS)

  # Every job in this app takes Active Record objects as arguments, so a record
  # deleted between enqueue and perform raises on deserialize before `perform`
  # is ever called. Deleting an account makes that routine rather than
  # exceptional — it takes twenty associations with it while recomputes for them
  # may still be queued — and there is nothing left to recompute, so the job is
  # finished, not failed.
  #
  # Logged rather than silent: if this starts appearing for a live account, the
  # records are disappearing some other way and that is worth seeing.
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.info(
      "#{job.class.name} discarded: the record it was queued for no longer exists (#{error.message})"
    )
  end
end
