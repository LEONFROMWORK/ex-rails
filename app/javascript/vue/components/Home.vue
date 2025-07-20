<template>
  <div class="container mx-auto p-6">
    <h1 class="text-4xl font-bold mb-8">{{ $t('home.title') }}</h1>
    
    <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
      <Card>
        <CardHeader>
          <CardTitle>{{ $t('home.excelProcessing') }}</CardTitle>
          <CardDescription>{{ $t('home.excelProcessingDesc') }}</CardDescription>
        </CardHeader>
        <CardContent>
          <p class="text-sm text-muted-foreground">
            {{ $t('home.useVueUploader') }}
          </p>
        </CardContent>
        <CardFooter>
          <Button @click="$router.push('/excel-uploader')">
            {{ $t('home.goToUploader') }}
          </Button>
        </CardFooter>
      </Card>
    </div>
  </div>
</template>

<script setup lang="ts">
import Card from '@/vue/components/ui/card/Card.vue'
import CardContent from '@/vue/components/ui/card/CardContent.vue'
import CardDescription from '@/vue/components/ui/card/CardDescription.vue'
import CardFooter from '@/vue/components/ui/card/CardFooter.vue'
import CardHeader from '@/vue/components/ui/card/CardHeader.vue'
import CardTitle from '@/vue/components/ui/card/CardTitle.vue'
import Button from '@/vue/components/ui/button/Button.vue'
</script>