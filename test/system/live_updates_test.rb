require "application_system_test_case"

# Four pages subscribe to the user's stream, and every recompute ends in
# `broadcast_refresh_to`, which Turbo applies as a morph. A morph rewrites form
# fields from the server's render, so before `unsaved-input` existed a wearable
# sync landing mid-check-in blanked all four ratings with nothing on screen to
# say why. These tests broadcast the same refresh the pipeline does.
class LiveUpdatesTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @oats = @user.foods.create!(
      name: "Zzz Live Oats", serving_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7
    )
  end

  test "a background refresh leaves an unfinished check-in alone" do
    @user.daily_readiness_inputs.where(metric_date: @user.local_date).destroy_all
    sign_in @user
    visit root_path

    within ".check-in__form" do
      choose_rating "Sleep quality", 4
      choose_rating "Muscle soreness", 2
      choose_rating "General fatigue", 3
      choose_rating "Life stress", 2
    end

    assert_equal 4, answered_ratings.size

    # A wearable sync materialising today broadcasts exactly this.
    count_morphs
    Turbo::StreamsChannel.broadcast_refresh_to(@user)
    await_morph

    assert_equal 4, answered_ratings.size,
      "the ratings the user had already answered survived the refresh"
  end

  test "a background refresh leaves half-typed nutrition input alone" do
    sign_in @user
    visit nutrition_path

    set_value "#food_log_entry_form [name='food_log_entry[quantity_grams]']", "137"
    set_value "#form_food [name='food[name]']", "Zzz Half Typed"
    set_value "#body_metric_form [name='body_metric[weight_kg]']", "83"

    count_morphs
    Turbo::StreamsChannel.broadcast_refresh_to(@user)
    await_morph

    assert_equal "137", value_of("#food_log_entry_form [name='food_log_entry[quantity_grams]']")
    assert_equal "Zzz Half Typed", value_of("#form_food [name='food[name]']")
    assert_equal "83", value_of("#body_metric_form [name='body_metric[weight_kg]']")
  end

  # The other half of the rule: a form that was submitted has to take the
  # server's fresh render, or the next entry opens on the last one's numbers.
  test "logging a food still clears the form for the next one" do
    sign_in @user
    visit nutrition_path

    select "Zzz Live Oats", from: "food_log_entry_food_id"
    set_value "#food_log_entry_form [name='food_log_entry[quantity_grams]']", "137"
    click_on "Log food"
    assert_text "Zzz Live Oats", wait: 10

    assert_equal "100", value_of("#food_log_entry_form [name='food_log_entry[quantity_grams]']"),
      "the logged quantity did not stick to the form"
  end

  # Submitting one form re-renders the page; the other form's input is not its
  # to throw away.
  test "logging a weigh-in leaves a half-typed food entry alone" do
    sign_in @user
    visit nutrition_path

    set_value "#food_log_entry_form [name='food_log_entry[quantity_grams]']", "137"
    set_value "#body_metric_form [name='body_metric[weight_kg]']", "83"
    click_on "Log weight"
    assert_text "Body weight logged", wait: 10

    assert_equal "137", value_of("#food_log_entry_form [name='food_log_entry[quantity_grams]']")
    assert_equal "", value_of("#body_metric_form [name='body_metric[weight_kg]']"),
      "the weigh-in form itself was submitted, so it takes the fresh render"
  end

  private

  def answered_ratings
    page.evaluate_script(
      "Array.from(document.querySelectorAll('.check-in__form input:checked')).map((el) => el.id)"
    )
  end

  def value_of(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json})?.value")
  end

  # Number inputs keep their prefilled value unless cleared first.
  def set_value(selector, value)
    field = find(selector, visible: :all)
    field.set("")
    field.set(value)
  end

  # A broadcast arrives over the socket, so there is no request for Capybara to
  # wait on. Counting Turbo's own morph event is the difference between waiting
  # long enough and hoping: a fixed sleep lets these tests pass by racing the
  # refresh rather than surviving it, which is how they passed against a
  # deliberately broken controller once.
  def count_morphs
    page.execute_script(<<~JS)
      window.__morphs = 0
      addEventListener("turbo:morph", () => { window.__morphs += 1 })
    JS
  end

  def await_morph
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until page.evaluate_script("window.__morphs").to_i.positive?
    end
  rescue Timeout::Error
    flunk "no turbo:morph arrived — the broadcast never reached the page"
  end

  def choose_rating(legend, value)
    find("fieldset", text: legend).find("label", text: value.to_s, match: :prefer_exact).click
  end
end
