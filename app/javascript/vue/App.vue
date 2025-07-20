<template>
  <div id="app">
    <router-view />
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useTheme } from './composables/useTheme'

// Initialize theme
const { initTheme } = useTheme()

onMounted(() => {
  initTheme()
  console.log('Vue App mounted successfully!')
})
</script>