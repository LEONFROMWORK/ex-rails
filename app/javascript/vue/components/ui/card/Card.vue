<template>
  <div :class="cn('rounded-lg border bg-card text-card-foreground shadow-sm', props.class)">
    <slot />
  </div>
</template>

<script setup lang="ts">
import { cn } from '@/vue/utils/cn'

interface CardProps {
  class?: string
}

const props = defineProps<CardProps>()
</script>