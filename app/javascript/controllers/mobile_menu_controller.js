import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="mobile-menu"
export default class extends Controller {
  static targets = ["menu", "overlay"]

  connect() {
    console.log("Mobile menu controller connected")
  }

  toggle() {
    if (this.hasMenuTarget) {
      this.menuTarget.classList.toggle("hidden")
    }
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.toggle("hidden")
    }
  }

  close() {
    if (this.hasMenuTarget) {
      this.menuTarget.classList.add("hidden")
    }
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
  }
}