class CoachingDecisionsController < ApplicationController
  def show
    # Scoped to the signed-in user: a decision is a record of someone's training,
    # and an id is guessable.
    @decision = Current.user.coaching_decisions.find(params[:id])
    @child_links = @decision.child_links.includes(:child_decision).order(:role, :id)
    # The decisions that cite this one. A user reading "why was this withdrawn"
    # needs to see what it fed as much as what it was built from.
    @parent_links = @decision.parent_links.includes(:parent_decision).order(:role, :id)
  end
end
