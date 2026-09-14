# Erases an account and everything in it.
#
# Every association on User already declares `dependent: :destroy`, but the
# cascade had never run, and two invariants that exist to protect a *live*
# account stand in its way. Both are deliberate, so both are lifted here
# deliberately rather than being weakened where they are declared:
#
#   - A decision that another decision cites cannot be deleted, at the model and
#     at the database. That is what stops evidence vanishing from under a live
#     recommendation. Erasure takes the citations with it, so the links go first.
#   - An exercise with logged sets against it cannot be deleted
#     (`restrict_with_error`), so you cannot lose a lift's history by tidying up
#     the catalogue. Erasure is meant to lose it, so the sessions go first.
#
# The order of the remaining associations is load-bearing too — Rails destroys
# them in declaration order, and several reference each other — so User declares
# them dependents-first and says so.
class AccountDeletion
  def initialize(user)
    @user = user
  end

  def call
    ApplicationRecord.transaction do
      release_cited_decisions
      release_logged_history
      # The guards above are lifted in the database, but `dependent:
      # :restrict_with_exception` asks the *association* whether it is empty —
      # and the objects used to build this account still hold loaded, now-stale
      # collections that say it is not. Reload so the cascade walks what the
      # database actually contains.
      user.reload.destroy!
    end
  end

  private

  attr_reader :user

  # Both ends of a link always belong to the same user — CoachingDecisionLink
  # validates it — so every link touching this account is reachable from its
  # decisions.
  def release_cited_decisions
    CoachingDecisionLink.where(parent_decision_id: user.coaching_decisions.select(:id)).delete_all
  end

  # Takes set entries with the sessions that hold them, which is what frees the
  # user's own exercises to be destroyed.
  def release_logged_history
    user.workout_sessions.destroy_all
  end
end
