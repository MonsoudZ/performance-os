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

  # A page's panels are a stack of cards down one column, so they share both
  # edges. `.form-panel` centres itself at 920px, which is right when the page is
  # only a form and wrong when the form is one section among panels — on the
  # block, goal and conditioning pages it sat 130px inside its neighbours on
  # both sides. Geometry, so only a browser can see it.
  test "the panels on a page line up with each other" do
    sign_in @user
    page.driver.resize(1400, 1100)

    ragged = pages.filter_map do |path|
      visit path
      edges = page.evaluate_script(<<~JS)
        (() => {
          const shell = document.querySelector("main.shell")
          if (!shell) return null
          const rows = Array.from(shell.children).filter((el) => {
            const box = el.getBoundingClientRect()
            return box.height > 0 && !el.classList.contains("page-heading") && el.tagName !== "HEADER"
          })
          const edges = rows.map((el) => ({
            what: el.tagName + "." + (el.className || "").split(" ")[0],
            left: Math.round(el.getBoundingClientRect().left),
            right: Math.round(el.getBoundingClientRect().right)
          }))
          const lefts = new Set(edges.map((e) => e.left))
          const rights = new Set(edges.map((e) => e.right))
          if (lefts.size <= 1 && rights.size <= 1) return null
          return edges.map((e) => `${e.what} ${e.left}→${e.right}`).join(", ")
        })()
      JS
      "#{path}: #{edges}" if edges
    end

    assert_empty ragged
  end

  # Controls here set `outline: none` and signalled focus with a border colour
  # and a halo measured at 1.18:1 against the white behind it. A keyboard user
  # who cannot see where they are is stuck, so the ring is asserted rather than
  # left to whoever next tidies the focus styles.
  #
  # The Tab presses are the point: `:focus-visible` is exactly the state a
  # script cannot fake, because Chrome decides it from how the element came to
  # be focused. Calling .focus() leaves every field reporting no outline.
  test "a keyboard user can see what is focused" do
    sign_in @user
    visit new_exercise_prescription_path

    reached = []
    30.times do
      page.driver.send_keys(:tab)
      field = page.evaluate_script(<<~JS)
        (() => {
          const el = document.activeElement
          if (!el || !el.closest(".stacked-form")) return null
          if (![ "INPUT", "SELECT", "TEXTAREA" ].includes(el.tagName)) return null
          if (el.type === "submit" || el.type === "checkbox") return null
          const style = getComputedStyle(el)
          return { name: el.name, ring: style.outlineStyle, width: parseFloat(style.outlineWidth) }
        })()
      JS
      reached << field if field
    end

    assert_operator reached.size, :>=, 3, "tabbing never reached the form's fields"
    assert_empty reached.reject { |f| f["ring"] != "none" && f["width"] >= 2 },
      "these were focused with no visible ring"
  end

  # Native controls draw themselves in the operating system's blue unless told
  # otherwise, and this app has twenty of them on the check-in alone.
  test "checkboxes and radios are painted in the app's own colour" do
    sign_in @user
    visit new_exercise_prescription_path

    assert_equal "rgb(36, 77, 63)",
      page.evaluate_script("getComputedStyle(document.querySelector('input[type=checkbox]')).accentColor")
  end

  private

  def pages
    [
      root_path, progress_path, exercise_prescriptions_path, workout_sessions_path,
      exercises_path, nutrition_path, meals_path, weekly_review_path, mesocycles_path,
      goal_periods_path, onboarding_path, edit_profile_path, conditioning_sessions_path,
      workout_templates_path, new_exercise_prescription_path, new_workout_session_path,
      new_meal_path, new_workout_template_path, readiness_inputs_path,
      wearable_devices_path, exercise_path(@user.exercises.first),
      workout_session_path(@user.workout_sessions.first),
      coaching_decision_path(@user.coaching_decisions.order(:id).last)
    ]
  end
end
