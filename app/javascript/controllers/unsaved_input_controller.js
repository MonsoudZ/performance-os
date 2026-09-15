import { Controller } from "@hotwired/stimulus"

// Holds a form against a background page refresh while it has input worth
// losing.
//
// Four pages subscribe to the user's stream, and every recompute ends in
// `broadcast_refresh_to`, which Turbo applies as a morph. A morph rewrites form
// fields from the server's render — so a wearable sync landing mid-check-in
// blanked all four ratings, with nothing on screen to say why.
//
// `data-turbo-permanent` is what tells Turbo to leave an element alone, but a
// form carrying it permanently would never pick up a fresh render either. So it
// goes on at the first keystroke and comes off at submit, when the response is
// the newer thing.
//
// The events are wired here rather than through `data-action` so a form opts in
// with one attribute and cannot half-subscribe — the same reason the flash
// controller owns its own default.
export default class extends Controller {
  connect() {
    this.hold = this.hold.bind(this)
    this.release = this.release.bind(this)

    this.release()
    this.element.addEventListener("input", this.hold)
    this.element.addEventListener("change", this.hold)
    this.element.addEventListener("submit", this.release)
    this.element.addEventListener("turbo:submit-start", this.release)
    this.element.addEventListener("reset", this.release)
  }

  disconnect() {
    this.element.removeEventListener("input", this.hold)
    this.element.removeEventListener("change", this.hold)
    this.element.removeEventListener("submit", this.release)
    this.element.removeEventListener("turbo:submit-start", this.release)
    this.element.removeEventListener("reset", this.release)
  }

  hold() {
    this.element.setAttribute("data-turbo-permanent", "")
  }

  release() {
    this.element.removeAttribute("data-turbo-permanent")
  }
}
