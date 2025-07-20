// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

// Import stimulus controllers lazily for better performance
import { Application } from "@hotwired/stimulus"
import { registerControllers } from "stimulus-loading"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

// Load controllers lazily
registerControllers(application, import.meta.glob("./controllers/**/*_controller.js"))

// Performance monitoring
if ('performance' in window) {
  // Monitor page load performance
  window.addEventListener('load', () => {
    const perfData = performance.getEntriesByType('navigation')[0];
    if (perfData && perfData.loadEventEnd > 0) {
      const loadTime = perfData.loadEventEnd - perfData.fetchStart;
      console.log(`Page load time: ${Math.round(loadTime)}ms`);
      
      // Send to analytics if available
      if (window.gtag) {
        gtag('event', 'page_load_time', {
          value: Math.round(loadTime),
          custom_parameter: 'performance'
        });
      }
    }
  });
  
  // Monitor resource loading
  const observer = new PerformanceObserver((list) => {
    list.getEntries().forEach((entry) => {
      if (entry.transferSize > 100000) { // Files larger than 100KB
        console.warn(`Large resource loaded: ${entry.name} (${Math.round(entry.transferSize / 1024)}KB)`);
      }
    });
  });
  observer.observe({ entryTypes: ['resource'] });
}

// Error handling and reporting
window.addEventListener('error', (event) => {
  console.error('JavaScript Error:', event.error);
  
  // Send to error tracking service if available
  if (window.Sentry) {
    Sentry.captureException(event.error);
  }
});

// Unhandled promise rejection handling
window.addEventListener('unhandledrejection', (event) => {
  console.error('Unhandled Promise Rejection:', event.reason);
  
  if (window.Sentry) {
    Sentry.captureException(event.reason);
  }
});

// Service Worker registration for PWA capabilities
if ('serviceWorker' in navigator && location.protocol === 'https:') {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/service-worker.js')
      .then((registration) => {
        console.log('SW registered: ', registration);
      })
      .catch((registrationError) => {
        console.log('SW registration failed: ', registrationError);
      });
  });
}

// Vue.js application initialization
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './vue/App.vue'
import router from './vue/router'
import './vue/assets/index.css'

// Initialize Vue app when DOM is ready
const initVueApp = () => {
  const vueElements = document.querySelectorAll('[data-vue-component]')
  
  vueElements.forEach(element => {
    const componentName = element.dataset.vueComponent
    const props = element.dataset.vueProps ? JSON.parse(element.dataset.vueProps) : {}
    
    // Dynamically import Vue components
    import(`./vue/components/${componentName}.vue`)
      .then(module => {
        const app = createApp(module.default, props)
        const pinia = createPinia()
        
        app.use(pinia)
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
