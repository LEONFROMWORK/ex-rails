<template>
  <div class="w-full max-w-2xl mx-auto p-6">
    <Card>
      <CardContent class="pt-6">
        <div class="text-center">
          <div class="mb-6">
            <XCircle :size="64" class="mx-auto text-red-500" />
          </div>
          
          <h1 class="text-2xl font-bold mb-2">{{ $t('payment.fail.title') }}</h1>
          <p class="text-muted-foreground mb-6">{{ $t('payment.fail.description') }}</p>
          
          <div v-if="errorMessage" class="mb-8">
            <Alert variant="destructive">
              <AlertCircle :size="16" />
              <AlertTitle>{{ $t('payment.fail.errorTitle') }}</AlertTitle>
              <AlertDescription>{{ errorMessage }}</AlertDescription>
            </Alert>
          </div>
          
          <div class="flex gap-3 justify-center">
            <Button @click="goBack" variant="outline">
              {{ $t('payment.fail.goBack') }}
            </Button>
            <Button @click="retry">
              {{ $t('payment.fail.retry') }}
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import Card from '@/vue/components/ui/card/Card.vue'
import CardContent from '@/vue/components/ui/card/CardContent.vue'
import Button from '@/vue/components/ui/button/Button.vue'
import Alert from '@/vue/components/ui/alert/Alert.vue'
import AlertDescription from '@/vue/components/ui/alert/AlertDescription.vue'
import AlertTitle from '@/vue/components/ui/alert/AlertTitle.vue'
import { XCircle, AlertCircle } from 'lucide-vue-next'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()

const errorMessage = ref('')

// Go back
const goBack = () => {
  router.back()
}

// Retry payment
const retry = () => {
  // Navigate to payment page or previous page
  router.back()
}

// Parse error from query params
const parseError = () => {
  const code = route.query.code as string
  const message = route.query.message as string
  
  if (code === 'PAY_PROCESS_CANCELED') {
    errorMessage.value = t('payment.fail.canceled')
  } else if (code === 'INVALID_CARD_NUMBER') {
    errorMessage.value = t('payment.fail.invalidCard')
  } else if (code === 'INSUFFICIENT_BALANCE') {
    errorMessage.value = t('payment.fail.insufficientBalance')
  } else if (message) {
    errorMessage.value = message
  } else {
    errorMessage.value = t('payment.fail.defaultError')
  }
}

onMounted(() => {
  parseError()
})
</script>