import { ref, watch } from 'vue'

const isDark = ref(false)

export function useTheme() {
  const initTheme = () => {
    // Check for saved theme preference or default to light
    const savedTheme = localStorage.getItem('theme')
    const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    
    isDark.value = savedTheme === 'dark' || (!savedTheme && systemPrefersDark)
    applyTheme(isDark.value)
  }
  
  const applyTheme = (dark: boolean) => {
    if (dark) {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }
  }
  
  const toggleTheme = () => {
    isDark.value = !isDark.value
    localStorage.setItem('theme', isDark.value ? 'dark' : 'light')
    applyTheme(isDark.value)
  }
  
  // Watch for theme changes
  watch(isDark, (newValue) => {
    applyTheme(newValue)
  })
  
  return {
    isDark,
    initTheme,
    toggleTheme
  }
}