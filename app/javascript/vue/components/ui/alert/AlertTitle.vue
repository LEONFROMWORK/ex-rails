<template>
  <h5 :class="cn('mb-1 font-medium leading-none tracking-tight', props.class)">
    <slot />
  </h5>
</template>

<script setup lang="ts">
import { cn } from '@/vue/utils/cn'

interface AlertTitleProps {
  class?: string
}

const props = defineProps<AlertTitleProps>()
</script>