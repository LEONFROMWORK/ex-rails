<template>
  <div :class="cn('text-sm [&_p]:leading-relaxed', props.class)">
    <slot />
  </div>
</template>

<script setup lang="ts">
import { cn } from '@/vue/utils/cn'

interface AlertDescriptionProps {
  class?: string
}

const props = defineProps<AlertDescriptionProps>()
</script>