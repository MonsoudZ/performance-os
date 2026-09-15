require "application_system_test_case"

# Nothing should scroll sideways on a phone. It is the failure that looks like
# nothing on a desktop and makes every page feel broken on the device most of
# this app is used from — and it is one property, so it is worth asserting over
# every page at once rather than remembering it per view.
class ResponsiveLayoutTest < ApplicationSystemTestCase
  include AccountFixture

  PHONE = [ 390, 844 ].freeze

  setup do
    @user = users(:one)
    populate_account(@user)
    # The pages are only as wide as what is on them, so the loops that render
    # rows of controls have to actually run.
    { "breakfast" => 2, "lunch" => 1 }.each do |meal_type, count|
      count.times do |index|
        @user.food_log_entries.create!(
          food: @user.foods.first, logged_at: Time.current - index.minutes, meal_type: meal_type,
          quantity_grams: 80 + index, source: "manual", kcal: 300, protein_g: 20, carb_g: 30, fat_g: 10
        )
      end
    end
  end

  test "no page scrolls sideways on a phone" do
    sign_in @user
    page.driver.resize(*PHONE)

    too_wide = pages.filter_map do |path|
      visit path
      overflow = page.evaluate_script(<<~JS)
        (() => {
          const root = document.documentElement
          if (root.scrollWidth <= root.clientWidth) return null
          const widest = Array.from(document.querySelectorAll("body *"))
            .map((el) => [ el, Math.round(el.getBoundingClientRect().right) ])
            .filter(([, right]) => right > root.clientWidth + 1)
            .sort((a, b) => b[1] - a[1])[0]
          return {
            page: root.scrollWidth, viewport: root.clientWidth,
            widest: widest ? widest[0].tagName + "." + widest[0].className : "unknown"
          }
        })()
      JS
      "#{path} is #{overflow['page']}px wide in a #{overflow['viewport']}px viewport (#{overflow['widest']})" if overflow
    end

    assert_empty too_wide
  end

  # Two navigations answering the same question is what a new topbar entry
  # breaks: the phone hides the topbar's links in favour of the thumb-reachable
  # tab bar, and a menu added to one without the other shows both at once.
  test "a phone offers one primary navigation, a desktop the other" do
    sign_in @user

    page.driver.resize(*PHONE)
    visit root_path
    assert_selector ".tabbar", visible: true
    assert_no_selector ".nav-menu", visible: true
    assert_no_selector ".nav-links a:not(.nav-links__primary)", visible: true

    page.driver.resize(1400, 900)
    visit root_path
    assert_no_selector ".tabbar", visible: true
    assert_selector ".nav-menu", visible: true, count: 4
  end

  private

  def pages
    [
      root_path, nutrition_path, meals_path, new_meal_path, progress_path,
      workout_templates_path, new_workout_template_path, workout_sessions_path,
      new_workout_session_path, exercises_path, exercise_prescriptions_path,
      mesocycles_path, conditioning_sessions_path, weekly_review_path,
      goal_periods_path, onboarding_path, edit_profile_path
    ]
  end
end
