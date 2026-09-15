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
    document.addEventListener("click", this.closeOnOutsideClick)
    document.addEventListener("keydown", this.closeOnEscape)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
    document.removeEventListener("keydown", this.closeOnEscape)
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
