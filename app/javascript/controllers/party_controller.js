import { Controller } from "@hotwired/stimulus"

// One pool-party block. "Plan the party" stays greyed out until a date is
// picked (everything else has a default). Picking the start date fills in the
// end date (same day; the end time defaults to 11:59 PM on the server). Editing
// a planned party swaps its red Delete back to "Plan the party" and hides its
// outlook until it's saved.
export default class extends Controller {
  static targets = ["startDate", "endDate", "submit", "delete", "outlook"]
  static values = { saved: Boolean }

  connect() {
    this.updateSubmit()
  }

  startDateChanged() {
    const start = this.startDateTarget.value
    if (start && (!this.endDateTarget.value || this.endDateTarget.value < start)) this.endDateTarget.value = start
    this.updateSubmit()
  }

  updateSubmit() {
    if (this.hasSubmitTarget) this.submitTarget.disabled = !this.startDateTarget.value
  }

  edited() {
    this.updateSubmit()
    if (!this.savedValue || this.dirty) return
    this.dirty = true
    this.submitTarget.hidden = false
    if (this.hasDeleteTarget) this.deleteTarget.hidden = true
    if (this.hasOutlookTarget) this.outlookTarget.hidden = true
    this.dispatch("editing", { bubbles: true })
  }
}
