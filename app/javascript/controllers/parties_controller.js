import { Controller } from "@hotwired/stimulus"

// The party list: while a saved party is being edited, hide the blank
// "new party" block so there's one thing to finish at a time.
export default class extends Controller {
  static targets = ["blank"]

  connect() {
    this.element.addEventListener("party:editing", () => { this.blankTarget.hidden = true })
  }
}
