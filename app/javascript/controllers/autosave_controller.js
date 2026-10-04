import { Controller } from "@hotwired/stimulus"

// Saves the settings form as soon as a field changes, then redraws the plan
// chart (a Turbo Frame) so the effect shows right away.
export default class extends Controller {
  static targets = ["status"]
  static values = { frame: String }

  async save() {
    this.statusTarget.textContent = "Saving…"
    this.statusTarget.className = "save-status muted"
    try {
      const response = await fetch(this.element.action, {
        method: "POST", // the form's hidden _method field makes it a PATCH
        body: new FormData(this.element),
        headers: { "Accept": "application/json" }
      })
      const result = await response.json()
      if (!response.ok) throw new Error((result.errors || ["Couldn't save"]).join(", "))
      this.statusTarget.textContent = "Saved ✓"
      this.statusTarget.className = "save-status ok"
      document.getElementById(this.frameValue)?.reload()
    } catch (error) {
      this.statusTarget.textContent = `Not saved: ${error.message}`
      this.statusTarget.className = "save-status error"
    }
  }
}
