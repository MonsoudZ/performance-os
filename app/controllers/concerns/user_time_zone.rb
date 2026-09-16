# Runs an action inside the user's own clock.
#
# Every day boundary in this app is the user's, never UTC's — the coach budget,
# the weekly review, the nutrition day, which meal a log is filed under. Most of
# those rules read `Time.current` and are correct only because the request is
# wrapped in `Time.use_zone`, which means the wrapping is not an optimisation to
# remember but the thing that makes them true.
#
# `ApplicationController` had it and `Api::V1::BaseController` did not, so the
# same rule meant two different things on the two surfaces: a 19:30 log in
# Denver was filed under dinner from a browser and under snack from the phone,
# because 19:30 in Denver is 01:30 UTC and `FoodLogEntry.meal_type_for` reads
# the hour it is handed. The phone's own nutrition endpoint said the meal
# happening now was dinner in the same round trip, because it asked
# `user.local_time` directly — so the API contradicted itself.
module UserTimeZone
  extend ActiveSupport::Concern

  private

  # UTC when nobody is signed in: there is no user to have a clock, and the
  # actions reachable that way (signing in, the public catalog) have no day
  # boundary in them.
  def use_user_time_zone(&action)
    Time.use_zone(Current.user&.time_zone || "UTC", &action)
  end
end
