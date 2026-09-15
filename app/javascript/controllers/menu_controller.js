import { Controller } from "@hotwired/stimulus"

// The topbar's grouped menus.
//
// `<details>` would need no JavaScript, which is why the phone's More sheet uses
// one, but a row of them stays open until clicked again: opening the next one
// leaves the last hanging over the page. A menu bar needs one open at a time,
// closing on Escape and on a click anywhere else.
export default class extends Controller {
  static targets = ["menu", "sheet", "trigger"]

  connect() {
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this)
    this.closeOnEscape = this.closeOnEscape.bind(this)
    this.closeOnFocusLeaving = this.closeOnFocusLeaving.bind(this)
    document.addEventListener("click", this.closeOnOutsideClick)
    document.addEventListener("keydown", this.closeOnEscape)
    this.element.addEventListener("focusout", this.closeOnFocusLeaving)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
    document.removeEventListener("keydown", this.closeOnEscape)
    this.element.removeEventListener("focusout", this.closeOnFocusLeaving)
  }

  toggle(event) {
    const sheet = this.sheetFor(event.target)
    const opening = sheet.hidden

    this.closeAll()
    if (opening) this.open(sheet)
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) this.closeAll()
  }

  // Tabbing past the last link used to leave the menu open behind you, covering
  // the page, with nothing focused inside it to say so. A mouse user gets the
  // click handler; this is the same courtesy for the keyboard.
  //
  // `relatedTarget` is what is about to take focus. It is null when focus
  // leaves the document altogether — switching windows — and a menu that shut
  // itself every time you alt-tabbed would be its own annoyance, so that case
  // is left to the click handler.
  closeOnFocusLeaving(event) {
    if (!event.relatedTarget) return
    if (this.element.contains(event.relatedTarget)) return

    this.closeAll()
  }

  closeOnEscape(event) {
    if (event.key !== "Escape") return

    const open = this.sheetTargets.find((sheet) => !sheet.hidden)
    if (!open) return

    this.closeAll()
    this.triggerFor(open).focus()
  }

  open(sheet) {
    sheet.hidden = false
    this.triggerFor(sheet).setAttribute("aria-expanded", "true")
  }

  closeAll() {
    this.sheetTargets.forEach((sheet) => {
      sheet.hidden = true
      this.triggerFor(sheet).setAttribute("aria-expanded", "false")
    })
  }

  sheetFor(node) {
    return this.menuTargets
      .find((menu) => menu.contains(node))
      .querySelector("[data-menu-target='sheet']")
  }

  triggerFor(sheet) {
    return this.menuTargets
      .find((menu) => menu.contains(sheet))
      .querySelector("[data-menu-target='trigger']")
  }
}
