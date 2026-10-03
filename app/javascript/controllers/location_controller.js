import { Controller } from "@hotwired/stimulus"

// Fills the pool form's location fields from the browser's geolocation or
// from a geocoding search result.
export default class extends Controller {
  static targets = ["name", "latitude", "longitude", "timeZone", "status"]

  locate(event) {
    event.preventDefault()
    if (!navigator.geolocation) {
      this.statusTarget.textContent = "This browser can't share its location."
      return
    }
    this.statusTarget.textContent = "Finding your location…"
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        const lat = coords.latitude.toFixed(4)
        const lon = coords.longitude.toFixed(4)
        this.fill(`Current location (${lat}, ${lon})`, lat, lon, Intl.DateTimeFormat().resolvedOptions().timeZone)
      },
      (error) => { this.statusTarget.textContent = `Couldn't get location: ${error.message}` }
    )
  }

  pick(event) {
    event.preventDefault()
    const { name, latitude, longitude, timeZone } = event.params
    this.fill(name, latitude, longitude, timeZone)
  }

  fill(name, latitude, longitude, timeZone) {
    this.nameTarget.value = name
    this.latitudeTarget.value = latitude
    this.longitudeTarget.value = longitude
    if (timeZone) this.timeZoneTarget.value = timeZone
    this.statusTarget.textContent = `Using ${name}. Save settings to keep it.`
  }
}
