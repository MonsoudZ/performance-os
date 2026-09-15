import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rows", "row", "template", "setIndex", "weight", "reps", "rir", "warmup", "volume", "search", "results"]
  // The inputs carry whatever unit the user reads, so the running total does too.
  static values = { unit: { type: String, default: "kg" } }

  connect() {
    this.nextIndex = this.rowTargets.length
    this.searchTimer = null
    this.updateVolume()
  }

  // Another set of *this* lift, so it belongs under this lift's last set — not
  // at the bottom of the session, below whatever else is being trained today.
  // Appending there put a third bench set after the squats and numbered it 3,
  // which read as a shuffle of a workout nobody performed that way.
  duplicateSet(event) {
    const row = event.target.closest("[data-workout-log-target='row']")
    this.appendRow({
      exerciseId: row.dataset.exerciseId,
      exerciseName: row.dataset.exerciseName,
      weight: row.querySelector("[data-workout-log-target='weight']")?.value,
      reps: row.querySelector("[data-workout-log-target='reps']")?.value,
      rir: row.querySelector("[data-workout-log-target='rir']")?.value
    }, this.lastRowFor(row.dataset.exerciseId))
  }

  lastRowFor(exerciseId) {
    return this.rowTargets.filter((row) => row.dataset.exerciseId === exerciseId).at(-1)
  }

  removeSet(event) {
    event.target.closest("[data-workout-log-target='row']").remove()
    this.renumberSets()
    this.updateVolume()
  }

  updateVolume() {
    const total = this.rowTargets.reduce((volume, row) => {
      const warmup = row.querySelector("[data-workout-log-target='warmup']")
      if (warmup?.checked) return volume

      const weight = Number(row.querySelector("[data-workout-log-target='weight']")?.value || 0)
      const reps = Number(row.querySelector("[data-workout-log-target='reps']")?.value || 0)
      return volume + (weight * reps)
    }, 0)

    this.volumeTarget.textContent = `${Math.round(total).toLocaleString()} ${this.unitValue}`
  }

  searchExercises() {
    window.clearTimeout(this.searchTimer)
    const query = this.searchTarget.value.trim()

    if (query.length < 2) {
      this.resultsTarget.replaceChildren()
      return
    }

    this.searchTimer = window.setTimeout(() => this.fetchExercises(query), 250)
  }

  async fetchExercises(query) {
    const response = await fetch(`/api/v1/exercises?query=${encodeURIComponent(query)}&limit=8`, {
      headers: { Accept: "application/json" }
    })
    if (!response.ok) return

    const payload = await response.json()
    this.resultsTarget.replaceChildren(...payload.data.map((exercise) => this.exerciseButton(exercise)))
  }

  exerciseButton(exercise) {
    const button = document.createElement("button")
    const name = document.createElement("strong")
    const modality = document.createElement("span")
    button.type = "button"
    button.className = "exercise-result"
    button.dataset.action = "workout-log#addExercise"
    button.dataset.exerciseId = exercise.id
    button.dataset.exerciseName = exercise.name
    name.textContent = exercise.name
    modality.textContent = exercise.modality
    button.append(name, modality)
    return button
  }

  addExercise(event) {
    this.appendRow({
      exerciseId: event.currentTarget.dataset.exerciseId,
      exerciseName: event.currentTarget.dataset.exerciseName
    })
    this.searchTarget.value = ""
    this.resultsTarget.replaceChildren()
  }

  // `after` is the row to slot in behind; without one the row goes at the end,
  // which is right for a movement that is not in the session yet.
  appendRow({ exerciseId, exerciseName, weight = "", reps = "", rir = "" }, after = null) {
    const html = this.templateTarget.innerHTML
      .replaceAll("NEW_RECORD", this.nextIndex)
      .replaceAll("EXERCISE_ID", exerciseId)
      .replaceAll("EXERCISE_NAME", exerciseName)

    if (after) {
      after.insertAdjacentHTML("afterend", html)
    } else {
      this.rowsTarget.insertAdjacentHTML("beforeend", html)
    }

    const row = after ? after.nextElementSibling : this.rowTargets[this.rowTargets.length - 1]
    row.querySelector("[data-workout-log-target='weight']").value = weight
    row.querySelector("[data-workout-log-target='reps']").value = reps
    row.querySelector("[data-workout-log-target='rir']").value = rir
    this.nextIndex += 1
    this.renumberSets()
    this.updateVolume()
  }

  renumberSets() {
    const exerciseCounts = new Map()

    this.rowTargets.forEach((row) => {
      const exerciseId = row.dataset.exerciseId
      const nextSet = (exerciseCounts.get(exerciseId) || 0) + 1
      exerciseCounts.set(exerciseId, nextSet)
      row.querySelector("[data-workout-log-target='setIndex']").value = nextSet
    })
  }
}
