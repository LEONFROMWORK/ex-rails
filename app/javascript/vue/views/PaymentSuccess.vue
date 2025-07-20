<template>
  <div class="w-full max-w-2xl mx-auto p-6">
    <Card>
      <CardContent class="pt-6">
        <div class="text-center">
          <div class="mb-6">
            <CheckCircle :size="64" class="mx-auto text-green-500" />
          </div>
          
          <h1 class="text-2xl font-bold mb-2">{{ $t('payment.success.title') }}</h1>
          <p class="text-muted-foreground mb-6">{{ $t('payment.success.description') }}</p>
          
          <div v-if="paymentData" class="mb-8 p-4 border rounded-lg bg-muted/50 text-left">
            <div class="space-y-2">
              <div class="flex justify-between">
                <span class="text-sm text-muted-foreground">{{ $t('payment.success.orderId') }}</span>
                <span class="text-sm font-medium">{{ paymentData.order_id }}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-muted-foreground">{{ $t('payment.success.amount') }}</span>
                <span class="text-sm font-medium">{{ formatAmount(paymentData.amount) }}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-muted-foreground">{{ $t('payment.success.approvedAt') }}</span>
                <span class="text-sm font-medium">{{ formatDate(paymentData.approved_at) }}</span>
              </div>
            </div>
          </div>
          
          <div class="flex gap-3 justify-center">
            <Button @click="goToHome" variant="outline">
              {{ $t('payment.success.goHome') }}
            </Button>
            <Button @click="viewReceipt" v-if="paymentData?.receipt_url">
              {{ $t('payment.success.viewReceipt') }}
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
import axios from 'axios'
import Card from '@/vue/components/ui/card/Card.vue'
import CardContent from '@/vue/components/ui/card/CardContent.vue'
import Button from '@/vue/components/ui/button/Button.vue'
import { CheckCircle } from 'lucide-vue-next'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const paymentData = ref<any>(null)
const isLoading = ref(true)

// Format amount
const formatAmount = (amount: number) => {
  return new Intl.NumberFormat(locale.value, {
    style: 'currency',
    currency: 'KRW'
  }).format(amount)
}

// Format date
const formatDate = (dateString: string) => {
  return new Date(dateString).toLocaleString(locale.value)
}

// Go to home
const goToHome = () => {
  router.push('/')
}

// View receipt
const viewReceipt = () => {
  if (paymentData.value?.receipt_url) {
    window.open(paymentData.value.receipt_url, '_blank')
  }
}

// Approve payment
const approvePayment = async () => {
  const paymentKey = route.query.paymentKey as string
  const orderId = route.query.orderId as string
  const amount = Number(route.query.amount)
  
  if (!paymentKey || !orderId || !amount) {
    router.push('/payments/fail')
    return
  }
  
  try {
    const response = await axios.post('/api/v1/payments/approve', {
      payment: {
        payment_key: paymentKey,
        order_id: orderId,
        amount: amount
      }
    }, {
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
      }
    })
    
    paymentData.value = response.data.data
  } catch (error) {
    console.error('Payment approval failed:', error)
    router.push('/payments/fail')
  } finally {
    isLoading.value = false
  }
}

onMounted(() => {
  approvePayment()
})
</script>