require "application_system_test_case"

# Two things that look like nothing in the markup and like an unfinished app on
# screen. Both are computed style, so only a browser can answer them.
class StylingTest < ApplicationSystemTestCase
  include AccountFixture

  BROWSER_DEFAULT_LINK = "rgb(0, 0, 238)".freeze

  setup do
    @user = users(:one)
    populate_account(@user)
  end

  # A link with no class, or one like .text-button that sets no colour, fell
  # back to the browser's blue-and-underlined — an exercise name rendering that
  # way inside an otherwise styled card. The base `a` rule decides this now, so
  # the guard is that no link is left looking like a 1994 hyperlink.
  test "no link falls back to the browser's own styling" do
    sign_in @user
    page.driver.resize(1400, 1000)

    unstyled = pages.flat_map do |path|
      visit path
      page.evaluate_script(<<~JS).map { |text| "#{path}: #{text}" }
        Array.from(document.querySelectorAll("a"))
          .filter((link) => {
            const style = getComputedStyle(link)
            return style.color === "#{BROWSER_DEFAULT_LINK}" || style.textDecorationLine === "underline"
          })
          .map((link) => link.textContent.trim().slice(0, 40))
      JS
    end

    assert_empty unstyled
  end

  # The logger's form is a .stacked-form, and that rule is one element more
  # specific than .set-field > span, so it won whatever the order: every row
  # printed "kg / Reps / RIR / Warm-up" above its fields, under a header row
  # already naming the columns. The per-field label is what the phone uses
  # instead of that header, so it has to survive there.
  test "the logger names each column once on a desktop and once on a phone" do
    sign_in @user

    page.driver.resize(1400, 1000)
    visit new_workout_session_path
    assert_selector ".set-table__header", visible: true
    assert_no_selector ".set-field > span", visible: true

    page.driver.resize(*ResponsiveLayoutTest::PHONE)
    visit new_workout_session_path
    assert_no_selector ".set-table__header", visible: true
    assert_selector ".set-field > span", visible: true
  end

  private

  def pages
    [
      root_path, progress_path, exercise_prescriptions_path, workout_sessions_path,
      exercises_path, nutrition_path, meals_path, weekly_review_path, mesocycles_path,
      goal_periods_path, onboarding_path, edit_profile_path, conditioning_sessions_path,
      workout_templates_path, new_exercise_prescription_path
    ]
  end
end
