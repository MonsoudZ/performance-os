class CoachingDecisionPruneJob < ApplicationJob
  queue_as :default

  # Bounds coaching_decisions growth WITHOUT breaking the auditable decision DAG.
  # Disabled by default — the product treats decisions as an immutable audit
  # trail, so pruning only happens when an operator opts in by setting
  # COACHING_DECISION_RETENTION_DAYS. Only decisions that nothing references as a
  # child (no parent_links) are removed, so the restrict_with_exception guard is
  # never violated; destroying a root cascades its child_links, freeing its
  # children for a later run.
  def perform(retention_days = ENV["COACHING_DECISION_RETENTION_DAYS"])
    return if retention_days.blank?

    cutoff = retention_days.to_i.days.ago
    deleted = 0

    CoachingDecision
      .where(created_at: ...cutoff)
      .where.missing(:parent_links)
      .in_batches(of: 500) { |batch| deleted += batch.destroy_all.size }

    Rails.logger.info("CoachingDecisionPruneJob removed #{deleted} decisions older than #{retention_days} days")
    deleted
  end
end
