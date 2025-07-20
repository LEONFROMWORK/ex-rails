import { createRouter, createWebHistory } from 'vue-router'
import type { RouteRecordRaw } from 'vue-router'

const routes: RouteRecordRaw[] = [
  {
    path: '/',
    name: 'home',
    component: () => import('../components/Home.vue')
  },
  {
    path: '/excel-uploader',
    name: 'excel-uploader',
    component: () => import('../components/ExcelUploader.vue')
  },
  {
    path: '/payment',
    name: 'payment',
    component: () => import('../components/TossPaymentWidget.vue')
  },
  {
    path: '/payments/success',
    name: 'payment-success',
    component: () => import('../views/PaymentSuccess.vue')
  },
  {
    path: '/payments/fail',
    name: 'payment-fail',
    component: () => import('../views/PaymentFail.vue')
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router