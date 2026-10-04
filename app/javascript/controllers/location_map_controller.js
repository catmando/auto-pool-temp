import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// Settings location picker: shows the chosen spot on a map. Search a ZIP code
// or city, use the device's location, or click the map; then Confirm saves it.
export default class extends Controller {
  static targets = ["map", "query", "latitude", "longitude", "name", "status", "confirm"]
  static values = { latitude: Number, longitude: Number, searchUrl: String }

  connect() {
    const located = this.hasLatitudeValue && this.latitudeValue !== 0
    const center = located ? [this.latitudeValue, this.longitudeValue] : [39.8, -98.6]
    this.map = L.map(this.mapTarget, { scrollWheelZoom: false }).setView(center, located ? 12 : 4)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)
    if (located) this.place(center[0], center[1], null, { save: false })
    this.map.on("click", (e) => this.place(e.latlng.lat, e.latlng.lng, ""))
  }

  disconnect() {
    this.map?.remove()
  }

  async search(event) {
    event.preventDefault()
    const query = this.queryTarget.value.trim()
    if (!query) return
    this.statusTarget.textContent = "Searching…"
    try {
      const response = await fetch(this.searchUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: JSON.stringify({ query })
      })
      const places = await response.json()
      if (!response.ok) throw new Error(places.error || response.statusText)
      if (places.length === 0) {
        this.statusTarget.textContent = `Nothing found for “${query}”.`
        return
      }
      const best = places[0]
      this.place(best.latitude, best.longitude, best.name)
    } catch (error) {
      this.statusTarget.textContent = `Search failed: ${error.message}`
    }
  }

  locate(event) {
    event.preventDefault()
    if (!navigator.geolocation) {
      this.statusTarget.textContent = "This browser can't share its location."
      return
    }
    this.statusTarget.textContent = "Finding your location…"
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => this.place(coords.latitude, coords.longitude, ""),
      (error) => { this.statusTarget.textContent = `Couldn't get your location: ${error.message}` }
    )
  }

  // Show a spot and get it ready to confirm. name "" means "look it up on save".
  place(lat, lng, name, { save = true } = {}) {
    this.marker?.remove()
    this.marker = L.circleMarker([lat, lng], { radius: 9, weight: 3, color: "#d1495b", fillOpacity: 0.35 }).addTo(this.map)
    this.map.setView([lat, lng], Math.max(this.map.getZoom(), 12))
    if (!save) return

    this.latitudeTarget.value = lat.toFixed(5)
    this.longitudeTarget.value = lng.toFixed(5)
    this.nameTarget.value = name || ""
    this.confirmTarget.disabled = false
    this.statusTarget.textContent = `${name || "This spot"}. Press Confirm to use it.`
  }
}
