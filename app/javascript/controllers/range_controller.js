import { Controller } from "@hotwired/stimulus"

// Shows the warmer/cooler slider's value as you drag it.
export default class extends Controller {
  static targets = ["input", "output"]

  show() {
    const value = Number(this.inputTarget.value)
    this.outputTarget.textContent = value === 0 ? "As is" : `${value > 0 ? "+" : "−"}${Math.abs(value)}°F`
  }
}
