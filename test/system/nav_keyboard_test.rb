require "application_system_test_case"

# The topbar menus are the one piece of navigation this app builds itself, so
# the behaviour a native control would give for free has to be provided and
# checked: reaching a menu, opening it, walking it, and getting out.
#
# A note on how these are driven. `page.driver.send_keys` fires a click on the
# document before it types, and that click is — correctly — an outside click,
# so the menu under test closes before the key arrives. Every early attempt at
# this file "found" bugs that were only that. Keys are dispatched as events
# here, which tests the controller's own handlers and nothing else; the parts
# a browser does natively (Tab moving focus, Enter clicking a button) are
# asserted structurally instead.
class NavKeyboardTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in @user
    page.driver.resize(1400, 1000)
    visit workout_templates_path
  end

  test "a closed menu keeps its links out of the way" do
    assert_equal 4, sheets.size
    assert(sheets.all? { |sheet| sheet["hidden"] }, "every menu starts closed")
    assert_equal 0, focusable_sheet_links, "a closed menu's links are not in the tab order"
  end

  # The trigger is a real button, so the browser gives it focus and Enter. What
  # has to be true for the keyboard is that the menu's own links are what comes
  # next — not the following trigger, with six destinations skipped.
  test "an open menu puts its own links next in the tab order" do
    find("button", text: "Training").click

    assert_equal [ "Workouts", "Training targets", "Exercises" ], next_tabbable_after_trigger(3)
  end

  test "escape closes the menu and hands focus back to the trigger" do
    find("button", text: "Training").click
    focus_first_link
    press_escape

    assert sheets.first["hidden"], "the menu closed"
    assert focused_the_first_trigger?, "focus went back to where it came from"
  end

  # Tabbing past the last link used to leave the menu hanging over the page.
  test "leaving the menu by keyboard closes it" do
    find("button", text: "Training").click
    focus_last_link
    assert_not sheets.first["hidden"], "still open while focus is inside"

    page.execute_script("document.querySelector('.brand').focus()")

    assert sheets.first["hidden"], "closed once focus moved out"
  end

  test "opening one menu closes the one already open" do
    find("button", text: "Training").click
    find("button", text: "Nutrition").click

    assert_equal [ "Nutrition" ], open_menu_labels
    assert_equal %w[false true false false], aria_expanded
  end

  private

  def sheets
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-menu-target=sheet]")).map((s) => ({ hidden: s.hidden }))
    JS
  end

  def focusable_sheet_links
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-menu-target=sheet] a"))
        .filter((a) => a.offsetParent !== null).length
    JS
  end

  def next_tabbable_after_trigger(count)
    page.evaluate_script(<<~JS)
      (() => {
        const selector = 'a[href],button:not([disabled]),input,select,textarea,[tabindex]:not([tabindex="-1"])'
        const tabbable = Array.from(document.querySelectorAll(selector)).filter((el) => el.offsetParent !== null)
        const trigger = document.querySelectorAll("[data-menu-target=trigger]")[0]
        const at = tabbable.indexOf(trigger)
        return tabbable.slice(at + 1, at + 1 + #{count}).map((el) => el.textContent.trim())
      })()
    JS
  end

  def open_menu_labels
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-menu-target=menu]"))
        .filter((menu) => !menu.querySelector("[data-menu-target=sheet]").hidden)
        .map((menu) => menu.querySelector("[data-menu-target=trigger]").textContent.trim().split(/\\s+/)[0])
    JS
  end

  def aria_expanded
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-menu-target=trigger]"))
        .map((t) => t.getAttribute("aria-expanded"))
    JS
  end

  def focus_first_link
    page.execute_script("document.querySelector('[data-menu-target=sheet] a').focus()")
  end

  def focus_last_link
    page.execute_script(<<~JS)
      const links = document.querySelectorAll("[data-menu-target=sheet]:not([hidden]) a")
      links[links.length - 1].focus()
    JS
  end

  def press_escape
    page.execute_script(<<~JS)
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    JS
  end

  def focused_the_first_trigger?
    page.evaluate_script("document.activeElement === document.querySelectorAll('[data-menu-target=trigger]')[0]")
  end
end
