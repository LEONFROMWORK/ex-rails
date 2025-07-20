import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "panel"]
  
  connect() {
    // Handle initial state
    this.isOpen = false
    
    // Add keyboard listener for escape key
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }
  
  disconnect() {
    // Clean up event listener
    document.removeEventListener("keydown", this.handleKeydown)
  }
  
  toggle(event) {
    if (event) event.preventDefault()
    this.isOpen ? this.close() : this.open()
  }
  
  open() {
    this.isOpen = true
    
    // Show backdrop
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.remove("opacity-0", "pointer-events-none")
      this.backdropTarget.classList.add("opacity-100", "pointer-events-auto")
    }
    
    // Show panel
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("translate-x-full")
      this.panelTarget.classList.add("translate-x-0")
    }
    
    // Prevent body scrolling on mobile
    if (window.innerWidth < 1024) {
      document.body.style.overflow = "hidden"
    }
  }
  
  close() {
    this.isOpen = false
    
    // Hide backdrop
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.remove("opacity-100", "pointer-events-auto")
      this.backdropTarget.classList.add("opacity-0", "pointer-events-none")
    }
    
    // Hide panel
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("translate-x-0")
      this.panelTarget.classList.add("translate-x-full")
    }
    
    // Restore body scrolling
    document.body.style.overflow = ""
  }
  
  handleKeydown(event) {
    // Close on escape key
    if (event.key === "Escape" && this.isOpen) {
      this.close()
    }
  }
}