// Import Stimulus
import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

// Import all Stimulus controllers
import ThemeController from '../controllers/theme_controller'
import TabsController from '../controllers/tabs_controller'
import MobileMenuController from '../controllers/mobile_menu_controller'

// Register controllers
application.register('theme', ThemeController)
application.register('tabs', TabsController)
application.register('mobile-menu', MobileMenuController)

// Vue.js application initialization
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from '../vue/App.vue'
import router from '../vue/router'
import { i18n } from '../vue/i18n'
import '../vue/assets/index.css'

// Initialize Vue app when DOM is ready
const initVueApp = () => {
  const vueElements = document.querySelectorAll('[data-vue-component]')
  
  vueElements.forEach(element => {
    const componentName = element.dataset.vueComponent
    const props = element.dataset.vueProps ? JSON.parse(element.dataset.vueProps) : {}
    
    // Dynamically import Vue components
    import(`../vue/components/${componentName}.vue`)
      .then(module => {
        const app = createApp(module.default, props)
        const pinia = createPinia()
        
        app.use(pinia)
        app.use(i18n)
        app.mount(element)
        
        // Store app instance for cleanup
        element.__vue_app__ = app
      })
      .catch(error => {
        console.error(`Failed to load Vue component ${componentName}:`, error)
      })
  })
  
  // Mount main Vue app if container exists
  const mainAppElement = document.getElementById('vue-app')
  if (mainAppElement) {
    const app = createApp(App)
    const pinia = createPinia()
    
    app.use(pinia)
    app.use(router)
    app.use(i18n)
    app.mount(mainAppElement)
    
    mainAppElement.__vue_app__ = app
  }
}

// Clean up Vue apps before Turbo caches the page
const cleanupVueApps = () => {
  document.querySelectorAll('[data-vue-component], #vue-app').forEach(element => {
    if (element.__vue_app__) {
      element.__vue_app__.unmount()
      delete element.__vue_app__
    }
  })
}

// Initialize on page load
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initVueApp)
} else {
  initVueApp()
}

// Handle Turbo navigation
document.addEventListener('turbo:load', initVueApp)
document.addEventListener('turbo:before-cache', cleanupVueApps)