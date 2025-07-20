<template>
  <div
    ref="progressRef"
    :class="cn('relative h-4 w-full overflow-hidden rounded-full bg-secondary', props.class)"
  >
    <div
      class="h-full w-full flex-1 bg-primary transition-all"
      :style="`transform: translateX(-${100 - (value || 0)}%)`"
    />
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { cn } from '@/vue/utils/cn'

interface ProgressProps {
  value?: number
  max?: number
  class?: string
}

const props = withDefaults(defineProps<ProgressProps>(), {
  value: 0,
  max: 100,
})

const progressRef = ref<HTMLDivElement>()
</script>