import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme"
export default class extends Controller {
  static values = { 
    value: String 
  }
  static targets = ["switch", "handle", "lightIcon", "darkIcon", "lightLabel", "darkLabel"]

  connect() {
    console.log('Theme controller connected!')
    
    // Check if theme is already applied from server
    const htmlElement = document.documentElement
    const currentTheme = htmlElement.classList.contains('dark') ? 'dark' : 'light'
    
    // Get stored theme or use current theme
    const storedTheme = this.getStoredTheme()
    const initialTheme = storedTheme || currentTheme
    
    console.log('Initial theme:', initialTheme, 'Current:', currentTheme, 'Stored:', storedTheme)
    
    // Only apply if different from current
    if (initialTheme !== currentTheme) {
      this.applyTheme(initialTheme)
    } else {
      // Just update the internal state
      this.currentTheme = initialTheme
    }
    
    // Always update UI and storage
    this.updateToggleUI(initialTheme)
    if (!storedTheme && currentTheme) {
      this.storeTheme(currentTheme)
      this.updateCookie(currentTheme)
    }
    
    // Listen for system theme changes
    this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    this.boundHandleChange = this.handleSystemThemeChange.bind(this)
    this.mediaQuery.addEventListener('change', this.boundHandleChange)
  }

  disconnect() {
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener('change', this.boundHandleChange)
    }
  }

  toggle() {
    console.log('Toggle clicked!')
    const currentTheme = this.getCurrentTheme()
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark'
    console.log('Toggling from', currentTheme, 'to', newTheme)
    this.setTheme(newTheme)
  }

  setTheme(theme) {
    this.applyTheme(theme)
    this.storeTheme(theme)
    this.updateCookie(theme)
    this.updateToggleUI(theme)
    
    // Dispatch custom event for other components
    this.dispatch('changed', { 
      detail: { theme } 
    })
  }

  applyTheme(theme) {
    const html = document.documentElement
    
    if (theme === 'dark') {
      html.classList.add('dark')
    } else {
      html.classList.remove('dark')
    }
    
    // Update theme-color meta tag for mobile browsers
    this.updateThemeColorMeta(theme)
    
    // Store current theme
    this.currentTheme = theme
  }

  getCurrentTheme() {
    return this.currentTheme || 
           this.getStoredTheme() || 
           this.getSystemTheme()
  }

  getStoredTheme() {
    return localStorage.getItem('theme')
  }

  getSystemTheme() {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }

  storeTheme(theme) {
    localStorage.setItem('theme', theme)
  }

  updateCookie(theme) {
    // Set cookie for server-side rendering
    document.cookie = `theme=${theme}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
  }

  updateThemeColorMeta(theme) {
    let metaThemeColor = document.querySelector('meta[name="theme-color"]')
    
    if (!metaThemeColor) {
      metaThemeColor = document.createElement('meta')
      metaThemeColor.name = 'theme-color'
      document.head.appendChild(metaThemeColor)
    }
    
    // Set appropriate theme color
    metaThemeColor.content = theme === 'dark' ? '#111827' : '#ffffff'
  }

  updateToggleUI(theme) {
    const isDark = theme === 'dark'
    
    // Update switch position and background
    if (this.hasHandleTarget) {
      if (isDark) {
        this.handleTarget.classList.remove('translate-x-0')
        // Adjust translate based on toggle size
        const translateClass = this.getTranslateClass()
        this.handleTarget.classList.add(translateClass)
      } else {
        const translateClass = this.getTranslateClass()
        this.handleTarget.classList.remove(translateClass)
        this.handleTarget.classList.add('translate-x-0')
      }
    }

    if (this.hasSwitchTarget) {
      if (isDark) {
        this.switchTarget.classList.remove('bg-muted')
        this.switchTarget.classList.add('bg-primary')
      } else {
        this.switchTarget.classList.remove('bg-primary')
        this.switchTarget.classList.add('bg-muted')
      }
      
      // Update aria-checked
      this.switchTarget.setAttribute('aria-checked', isDark.toString())
    }
  }

  handleSystemThemeChange(event) {
    // Only auto-switch if user hasn't manually set a preference
    if (!this.getStoredTheme()) {
      const newTheme = event.matches ? 'dark' : 'light'
      this.applyTheme(newTheme)
      this.updateToggleUI(newTheme)
    }
  }

  // Action to set specific theme
  setLight() {
    this.setTheme('light')
  }

  setDark() {
    this.setTheme('dark')
  }

  setSystem() {
    // Remove stored preference to follow system
    localStorage.removeItem('theme')
    this.updateCookie('system')
    
    const systemTheme = this.getSystemTheme()
    this.applyTheme(systemTheme)
    this.updateToggleUI(systemTheme)
    
    this.dispatch('changed', { 
      detail: { theme: 'system', resolved: systemTheme } 
    })
  }

  // Helper method to check if dark mode is active
  get isDark() {
    return this.getCurrentTheme() === 'dark'
  }

  // Helper method to check if light mode is active
  get isLight() {
    return this.getCurrentTheme() === 'light'
  }

  // Get appropriate translate class based on toggle size
  getTranslateClass() {
    // Check parent element for size indicators
    const parent = this.element
    if (parent.querySelector('.h-5.w-9')) {
      return 'translate-x-4' // small
    } else if (parent.querySelector('.h-7.w-12')) {
      return 'translate-x-5' // large
    } else {
      return 'translate-x-5' // medium (default)
    }
  }
}