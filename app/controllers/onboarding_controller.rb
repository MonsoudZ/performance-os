class OnboardingController < ApplicationController
  def show
    @progress = OnboardingProgress.new(Current.user)
  end
end
