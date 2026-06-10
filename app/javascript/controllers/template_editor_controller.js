import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rows", "row", "template", "position"]

  connect() {
    this.nextIndex = this.rowTargets.length
    this.updatePositions()
  }

  add() {
    const html = this.templateTarget.innerHTML.replaceAll("NEW_RECORD", this.nextIndex)
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.nextIndex += 1
    this.updatePositions()
  }

  remove(event) {
    const row = event.target.closest("[data-template-editor-target='row']")
    const destroyField = row.querySelector("[name$='[_destroy]']")

    if (destroyField) {
      destroyField.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }

    this.updatePositions()
  }

  moveUp(event) {
    const row = event.target.closest("[data-template-editor-target='row']")
    const visibleRows = this.visibleRows()
    const index = visibleRows.indexOf(row)
    if (index > 0) this.rowsTarget.insertBefore(row, visibleRows[index - 1])
    this.updatePositions()
  }

  moveDown(event) {
    const row = event.target.closest("[data-template-editor-target='row']")
    const visibleRows = this.visibleRows()
    const index = visibleRows.indexOf(row)
    if (index < visibleRows.length - 1) this.rowsTarget.insertBefore(visibleRows[index + 1], row)
    this.updatePositions()
  }

  updatePositions() {
    this.visibleRows().forEach((row, index) => {
      row.querySelector("[data-template-editor-target='position']").value = index + 1
    })
  }

  visibleRows() {
    return this.rowTargets.filter((row) => !row.hidden)
  }
}
