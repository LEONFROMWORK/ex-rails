<template>
  <div class="w-full max-w-2xl mx-auto p-6">
    <Card>
      <CardHeader>
        <CardTitle>{{ $t('excel.uploader.title') }}</CardTitle>
        <CardDescription>
          {{ $t('excel.uploader.description') }}
        </CardDescription>
      </CardHeader>
      
      <CardContent>
        <div
          @drop="handleDrop"
          @dragover.prevent
          @dragenter.prevent
          :class="cn(
            'border-2 border-dashed rounded-lg p-8 text-center transition-colors',
            isDragging ? 'border-primary bg-primary/5' : 'border-border',
            'hover:border-primary hover:bg-primary/5'
          )"
        >
          <Upload :size="48" class="mx-auto mb-4 text-muted-foreground" />
          
          <p class="text-lg font-medium mb-2">
            {{ $t('excel.uploader.dragDrop') }}
          </p>
          
          <p class="text-sm text-muted-foreground mb-4">
            {{ $t('excel.uploader.orClick') }}
          </p>
          
          <input
            ref="fileInput"
            type="file"
            accept=".xlsx,.xls,.csv"
            @change="handleFileSelect"
            class="hidden"
          />
          
          <Button @click="$refs.fileInput.click()" variant="secondary">
            {{ $t('excel.uploader.selectFile') }}
          </Button>
        </div>
        
        <div v-if="selectedFile" class="mt-6">
          <div class="flex items-center justify-between p-4 border rounded-lg">
            <div class="flex items-center gap-3">
              <FileSpreadsheet :size="24" class="text-primary" />
              <div>
                <p class="font-medium">{{ selectedFile.name }}</p>
                <p class="text-sm text-muted-foreground">
                  {{ formatFileSize(selectedFile.size) }}
                </p>
              </div>
            </div>
            
            <Button
              @click="removeFile"
              variant="ghost"
              size="icon"
            >
              <X :size="20" />
            </Button>
          </div>
        </div>
        
        <Alert v-if="error" variant="destructive" class="mt-4">
          <AlertCircle :size="16" />
          <AlertTitle>Error</AlertTitle>
          <AlertDescription>{{ error }}</AlertDescription>
        </Alert>
      </CardContent>
      
      <CardFooter class="flex justify-end gap-2">
        <Button
          @click="resetForm"
          variant="outline"
          :disabled="!selectedFile && !error"
        >
          {{ $t('common.reset') }}
        </Button>
        
        <Button
          @click="uploadFile"
          :disabled="!selectedFile || isUploading"
        >
          <Loader2 v-if="isUploading" :size="16" class="mr-2 animate-spin" />
          {{ isUploading ? $t('excel.uploader.uploading') : $t('excel.uploader.uploadFile') }}
        </Button>
      </CardFooter>
    </Card>
    
    <Progress
      v-if="uploadProgress > 0 && uploadProgress < 100"
      :value="uploadProgress"
      class="mt-4"
    />
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import axios from 'axios'
import { useI18n } from 'vue-i18n'
import { cn } from '@/vue/utils/cn'
import Card from '@/vue/components/ui/card/Card.vue'
import CardContent from '@/vue/components/ui/card/CardContent.vue'
import CardDescription from '@/vue/components/ui/card/CardDescription.vue'
import CardFooter from '@/vue/components/ui/card/CardFooter.vue'
import CardHeader from '@/vue/components/ui/card/CardHeader.vue'
import CardTitle from '@/vue/components/ui/card/CardTitle.vue'
import Button from '@/vue/components/ui/button/Button.vue'
import Alert from '@/vue/components/ui/alert/Alert.vue'
import AlertDescription from '@/vue/components/ui/alert/AlertDescription.vue'
import AlertTitle from '@/vue/components/ui/alert/AlertTitle.vue'
import Progress from '@/vue/components/ui/progress/Progress.vue'
import { 
  Upload, 
  FileSpreadsheet, 
  X, 
  AlertCircle,
  Loader2 
} from 'lucide-vue-next'

const { t } = useI18n()
const isDragging = ref(false)
const selectedFile = ref<File | null>(null)
const error = ref('')
const isUploading = ref(false)
const uploadProgress = ref(0)
const fileInput = ref<HTMLInputElement>()

const handleDrop = (e: DragEvent) => {
  e.preventDefault()
  isDragging.value = false
  
  const files = e.dataTransfer?.files
  if (files && files.length > 0) {
    handleFile(files[0])
  }
}

const handleFileSelect = (e: Event) => {
  const target = e.target as HTMLInputElement
  const files = target.files
  if (files && files.length > 0) {
    handleFile(files[0])
  }
}

const handleFile = (file: File) => {
  error.value = ''
  
  // Validate file type
  const validTypes = [
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
    'text/csv'
  ]
  
  if (!validTypes.includes(file.type)) {
    error.value = t('excel.uploader.invalidFileType')
    return
  }
  
  // Validate file size (max 10MB)
  const maxSize = 10 * 1024 * 1024
  if (file.size > maxSize) {
    error.value = t('excel.uploader.fileSizeError')
    return
  }
  
  selectedFile.value = file
}

const removeFile = () => {
  selectedFile.value = null
  error.value = ''
  if (fileInput.value) {
    fileInput.value.value = ''
  }
}

const resetForm = () => {
  removeFile()
  uploadProgress.value = 0
}

const formatFileSize = (bytes: number): string => {
  if (bytes === 0) return '0 Bytes'
  
  const k = 1024
  const sizes = ['Bytes', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const uploadFile = async () => {
  if (!selectedFile.value) return
  
  isUploading.value = true
  error.value = ''
  uploadProgress.value = 0
  
  const formData = new FormData()
  formData.append('file', selectedFile.value)
  
  try {
    const response = await axios.post('/api/excel/upload', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
      },
      onUploadProgress: (progressEvent) => {
        if (progressEvent.total) {
          uploadProgress.value = Math.round((progressEvent.loaded * 100) / progressEvent.total)
        }
      }
    })
    
    // Handle successful upload
    console.log('Upload successful:', response.data)
    
    // Reset form after successful upload
    setTimeout(() => {
      resetForm()
    }, 1000)
    
  } catch (err) {
    console.error('Upload error:', err)
    error.value = t('excel.uploader.uploadError')
    uploadProgress.value = 0
  } finally {
    isUploading.value = false
  }
}
</script>