# What a native client may say about a check-in, and the two rules about saying
# it badly. Shared by the endpoint that answers today and the one that corrects
# an earlier day, because the rules are the same and a second copy is how the
# `source` rule ended up with three.
module ReadinessAnswers
  extend ActiveSupport::Concern

  private

  def readiness_params
    params.require(:daily_readiness_input)
      .permit(:sleep_hours, *DailyReadinessInput::SUBJECTIVE_FIELDS)
  end

  # A blank sleep figure is dropped rather than assigned. There is no form here
  # to distinguish "I cleared this" from "I left it out", and the watch may
  # already have measured the night — erasing that on a request that never
  # mentioned it would throw away evidence to record an absence.
  def readiness_attributes
    attributes = readiness_params.to_h
    attributes.delete("sleep_hours") if attributes["sleep_hours"].blank?
    attributes
  end

  # Ratings the request named and then left empty. Blanking one turns a day the
  # user answered into a day they half-answered, which still gets scored — from
  # less than they actually know. The web form's `required` attributes make this
  # unreachable there; nothing makes it unreachable here except this.
  def blanked_ratings
    DailyReadinessInput::SUBJECTIVE_FIELDS.select do |field|
      readiness_params.key?(field.to_s) && readiness_params[field].blank?
    end
  end

  def unanswerable(fields, reason)
    render json: {
      error: "Check-in is incomplete",
      details: fields.map { |field| "#{field.to_s.humanize} #{reason}" }
    }, status: :unprocessable_entity
  end
end
