<template>
  <h3 :class="cn('text-2xl font-semibold leading-none tracking-tight', props.class)">
    <slot />
  </h3>
</template>

<script setup lang="ts">
import { cn } from '@/vue/utils/cn'

interface CardTitleProps {
  class?: string
}

const props = defineProps<CardTitleProps>()
</script>