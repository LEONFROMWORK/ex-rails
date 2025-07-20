<template>
  <div class="w-full max-w-2xl mx-auto p-6">
    <Card>
      <CardHeader>
        <CardTitle>{{ $t('payment.widget.title') }}</CardTitle>
        <CardDescription>
          {{ $t('payment.widget.description') }}
        </CardDescription>
      </CardHeader>
      
      <CardContent>
        <div v-if="!paymentWidget" class="text-center py-8">
          <Loader2 :size="32" class="mx-auto mb-4 animate-spin text-muted-foreground" />
          <p class="text-sm text-muted-foreground">{{ $t('payment.widget.loading') }}</p>
        </div>
        
        <div v-else>
          <!-- Payment Method Selection -->
          <div id="payment-method-widget" class="mb-6"></div>
          
          <!-- Agreement -->
          <div id="agreement-widget" class="mb-6"></div>
          
          <!-- Payment Amount -->
          <div class="mb-6 p-4 border rounded-lg bg-muted/50">
            <div class="flex justify-between items-center mb-2">
              <span class="text-sm font-medium">{{ $t('payment.widget.orderName') }}</span>
              <span class="text-sm">{{ orderName }}</span>
            </div>
            <div class="flex justify-between items-center">
              <span class="font-medium">{{ $t('payment.widget.totalAmount') }}</span>
              <span class="text-lg font-bold text-primary">{{ formatAmount(amount) }}</span>
            </div>
          </div>
          
          <!-- Payment Button -->
          <Button 
            @click="requestPayment" 
            :disabled="isProcessing"
            class="w-full"
            size="lg"
          >
            <Loader2 v-if="isProcessing" :size="16" class="mr-2 animate-spin" />
            {{ isProcessing ? $t('payment.widget.processing') : $t('payment.widget.payButton', { amount: formatAmount(amount) }) }}
          </Button>
        </div>
        
        <Alert v-if="error" variant="destructive" class="mt-4">
          <AlertCircle :size="16" />
          <AlertTitle>{{ $t('payment.widget.error') }}</AlertTitle>
          <AlertDescription>{{ error }}</AlertDescription>
        </Alert>
      </CardContent>
    </Card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
// import { loadPaymentWidget } from '@tosspayments/payment-widget-sdk'
import { useI18n } from 'vue-i18n'
import axios from 'axios'
import Card from '@/vue/components/ui/card/Card.vue'
import CardContent from '@/vue/components/ui/card/CardContent.vue'
import CardDescription from '@/vue/components/ui/card/CardDescription.vue'
import CardHeader from '@/vue/components/ui/card/CardHeader.vue'
import CardTitle from '@/vue/components/ui/card/CardTitle.vue'
import Button from '@/vue/components/ui/button/Button.vue'
import Alert from '@/vue/components/ui/alert/Alert.vue'
import AlertDescription from '@/vue/components/ui/alert/AlertDescription.vue'
import AlertTitle from '@/vue/components/ui/alert/AlertTitle.vue'
import { AlertCircle, Loader2 } from 'lucide-vue-next'

// Props
interface Props {
  amount: number
  orderName: string
  customerName?: string
  customerEmail?: string
  successUrl?: string
  failUrl?: string
}

const props = withDefaults(defineProps<Props>(), {
  successUrl: '/payments/success',
  failUrl: '/payments/fail'
})

// Emits
const emit = defineEmits<{
  success: [payment: any]
  error: [error: Error]
}>()

const { t, locale } = useI18n()
const paymentWidget = ref<any>(null)
const error = ref('')
const isProcessing = ref(false)

// Format amount with currency
const formatAmount = (amount: number) => {
  return new Intl.NumberFormat(locale.value, {
    style: 'currency',
    currency: 'KRW'
  }).format(amount)
}

// Initialize payment widget
const initializeWidget = async () => {
  try {
    // Get client key from backend
    const response = await axios.post('/api/v1/payments/request', {
      payment: {
        amount: props.amount,
        order_name: props.orderName,
        payment_method: 'card',
        success_url: props.successUrl,
        fail_url: props.failUrl
      }
    }, {
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
      }
    })
    
    const { client_key, order_id } = response.data.data
    
    // Load payment widget
    // const widget = await loadPaymentWidget(client_key, props.customerEmail || 'ANONYMOUS')
    // Temporary placeholder for disabled payment feature
    const widget = {
      renderPaymentMethods: async () => {},
      renderAgreement: async () => {},
      requestPayment: async () => { throw new Error('Payment feature is currently disabled') }
    }
    
    // Render payment method widget
    await widget.renderPaymentMethods('#payment-method-widget', props.amount)
    
    // Render agreement widget
    await widget.renderAgreement('#agreement-widget')
    
    paymentWidget.value = {
      widget,
      orderId: order_id
    }
  } catch (err) {
    console.error('Failed to initialize payment widget:', err)
    error.value = t('payment.widget.initError')
    emit('error', err as Error)
  }
}

// Request payment
const requestPayment = async () => {
  if (!paymentWidget.value) return
  
  isProcessing.value = true
  error.value = ''
  
  try {
    // Request payment through widget
    await paymentWidget.value.widget.requestPayment({
      orderId: paymentWidget.value.orderId,
      orderName: props.orderName,
      successUrl: window.location.origin + props.successUrl,
      failUrl: window.location.origin + props.failUrl,
      customerEmail: props.customerEmail,
      customerName: props.customerName,
      amount: props.amount
    })
  } catch (err: any) {
    console.error('Payment request failed:', err)
    
    // Handle specific error codes
    if (err.code === 'USER_CANCEL') {
      error.value = t('payment.widget.userCancel')
    } else if (err.code === 'INVALID_CARD_NUMBER') {
      error.value = t('payment.widget.invalidCard')
    } else {
      error.value = err.message || t('payment.widget.paymentError')
    }
    
    emit('error', err)
  } finally {
    isProcessing.value = false
  }
}

// Lifecycle
onMounted(() => {
  initializeWidget()
})

onUnmounted(() => {
  // Clean up if needed
  paymentWidget.value = null
})
</script>