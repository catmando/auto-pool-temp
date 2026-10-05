import { Controller } from "@hotwired/stimulus"

// One pool-party block. "Plan the party" stays greyed out until a date is
// picked (everything else has a default). The end date tracks the start date:
// the first pick copies it, and moving the start later moves the end by the
// same number of days (either direction), keeping the party's length. The end
// time defaults to 11:59 PM on the server. Until can't go before the start: the
// date picker won't offer earlier dates, and an Until at or before the start is
// flagged and keeps "Plan the party" greyed out. Editing a planned party swaps its red
// Delete back to "Plan the party" and hides its outlook until it's saved.
export default class extends Controller {
  static targets = ["startDate", "startTime", "endDate", "endTime", "submit", "delete", "outlook", "error"]
  static values = { saved: Boolean }

  connect() {
    this.previousStart = this.startDateTarget.value
    this.updateSubmit()
    this.element.dataset.partyReady = "true" // lets browser specs wait until the block is live
  }

  startDateChanged() {
    const start = this.startDateTarget.value
    const end = this.endDateTarget.value
    if (start && this.previousStart && end) {
      this.endDateTarget.value = shiftDate(end, daysBetween(this.previousStart, start))
    } else if (start) {
      this.endDateTarget.value = start
    }
    if (start) this.previousStart = start
    this.updateSubmit()
  }

  // Greyed out until there's a date, and while Until isn't after the start.
  updateSubmit() {
    const start = this.startDateTarget.value
    this.endDateTarget.min = start
    const bad = start && !this.endsAfterStart()
    this.endDateTarget.setCustomValidity(bad ? "The party has to end after it starts." : "")
    if (this.hasErrorTarget) this.errorTarget.hidden = !bad
    if (this.hasSubmitTarget) this.submitTarget.disabled = !start || bad
  }

  // Blank times use the server's defaults (noon start, 11:59 PM end); a blank
  // Until date means the start date.
  endsAfterStart() {
    const start = `${this.startDateTarget.value}T${this.timeOf(this.startTimeTarget, "12:00")}`
    const end = `${this.endDateTarget.value || this.startDateTarget.value}T${this.timeOf(this.endTimeTarget, "23:59")}`
    return end > start
  }

  timeOf(field, fallback) {
    return field?.value || fallback
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

// Dates are "YYYY-MM-DD"; do the arithmetic in UTC so daylight saving can't shift a day.
function daysBetween(from, to) {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000)
}

function shiftDate(date, days) {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * 86400000).toISOString().slice(0, 10)
}
