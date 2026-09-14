import { Controller } from "@hotwired/stimulus"

// Dismisses a flash message: on the close button always, and on a timer for the
// ones that only report that something went right.
//
// An error the user has to act on stays until they close it — auto-hiding
// "That password is not right" would take the explanation away from the person
// still typing.
export default class extends Controller {
  static values = {
    // Milliseconds before the message goes by itself. 0 means never, which is
    // the default so that opting out of it is not something a view can forget.
    dismissAfter: { type: Number, default: 0 },
    // Long enough for the fade to finish; the element is removed either way, so
    // a browser that skips the transition still gets rid of it.
    leaveDuration: { type: Number, default: 200 }
  }

  connect() {
    if (this.dismissAfterValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.dismissAfterValue)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.removal)
  }

  dismiss() {
    clearTimeout(this.timer)
    // Removed rather than hidden: a class that sets `display` outranks the user
    // agent's [hidden] rule, which has already left one element on screen here.
    this.element.classList.add("flash--leaving")
    this.removal = setTimeout(() => this.element.remove(), this.leaveDurationValue)
  }
}
