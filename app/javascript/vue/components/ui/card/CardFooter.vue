<template>
  <div :class="cn('flex items-center p-6 pt-0', props.class)">
    <slot />
  </div>
</template>

<script setup lang="ts">
import { cn } from '@/vue/utils/cn'

interface CardFooterProps {
  class?: string
}

const props = defineProps<CardFooterProps>()
</script>