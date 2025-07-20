import { Controller } from "@hotwired/stimulus"

// Modern Excel modification controller with screenshot support
export default class extends Controller {
  static targets = [
    "fileInfo", 
    "screenshotPreview", 
    "screenshotInput",
    "requestInput", 
    "submitButton",
    "loadingState",
    "resultSection",
    "errorMessage",
    "tierSelection",
    "tierInput"
  ]

  connect() {
    this.fileId = this.data.get("fileId")
    this.apiEndpoint = this.data.get("apiEndpoint") || "/api/v1/excel_modifications/modify"
    this.setupEventListeners()
  }

  setupEventListeners() {
    // Screenshot drag & drop
    if (this.hasScreenshotPreviewTarget) {
      this.screenshotPreviewTarget.addEventListener('dragover', this.handleDragOver.bind(this))
      this.screenshotPreviewTarget.addEventListener('drop', this.handleDrop.bind(this))
    }

    // Paste event for screenshots
    document.addEventListener('paste', this.handlePaste.bind(this))
  }

  // Handle file selection
  selectScreenshot() {
    this.screenshotInputTarget.click()
  }

  // Handle screenshot change
  screenshotChanged(event) {
    const file = event.target.files[0]
    if (file && file.type.startsWith('image/')) {
      this.displayScreenshot(file)
    }
  }

  // Handle drag over
  handleDragOver(event) {
    event.preventDefault()
    event.currentTarget.classList.add('border-blue-500', 'bg-blue-50')
  }

  // Handle drop
  handleDrop(event) {
    event.preventDefault()
    event.currentTarget.classList.remove('border-blue-500', 'bg-blue-50')
    
    const file = event.dataTransfer.files[0]
    if (file && file.type.startsWith('image/')) {
      this.displayScreenshot(file)
    }
  }

  // Handle paste (for screenshots)
  handlePaste(event) {
    const items = event.clipboardData.items
    for (let item of items) {
      if (item.type.startsWith('image/')) {
        const file = item.getAsFile()
        this.displayScreenshot(file)
        break
      }
    }
  }

  // Display screenshot preview
  displayScreenshot(file) {
    const reader = new FileReader()
    reader.onload = (e) => {
      this.screenshotData = e.target.result
      this.screenshotPreviewTarget.innerHTML = `
        <div class="relative">
          <img src="${e.target.result}" alt="Screenshot" class="max-w-full h-auto rounded-lg shadow-md">
          <button type="button" 
                  class="absolute top-2 right-2 bg-red-500 text-white rounded-full p-2 hover:bg-red-600"
                  data-action="click->excel-modification#removeScreenshot">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>
      `
      this.validateForm()
    }
    reader.readAsDataURL(file)
  }

  // Remove screenshot
  removeScreenshot() {
    this.screenshotData = null
    this.screenshotPreviewTarget.innerHTML = `
      <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center cursor-pointer hover:border-gray-400"
           data-action="click->excel-modification#selectScreenshot">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path>
        </svg>
        <p class="mt-2 text-sm text-gray-600">클릭하거나 드래그하여 스크린샷 업로드</p>
        <p class="text-xs text-gray-500">또는 Ctrl+V로 붙여넣기</p>
      </div>
    `
    this.validateForm()
  }

  // Validate form
  validateForm() {
    const hasScreenshot = !!this.screenshotData
    const hasRequest = this.requestInputTarget.value.trim().length > 0
    
    this.submitButtonTarget.disabled = !(hasScreenshot && hasRequest)
    
    if (hasScreenshot && hasRequest) {
      this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
    } else {
      this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
    }
  }

  // Handle request input change
  requestChanged(event) {
    // Character counter
    const length = event.target.value.length
    const maxLength = 500
    
    let counter = this.element.querySelector('[data-character-counter]')
    if (!counter) {
      counter = document.createElement('div')
      counter.setAttribute('data-character-counter', true)
      counter.className = 'text-sm text-gray-500 mt-1 text-right'
      event.target.parentNode.appendChild(counter)
    }
    
    counter.textContent = `${length} / ${maxLength}`
    
    // Validate
    this.validateForm()
  }

  // Submit modification request
  async submitModification() {
    // Validate inputs
    if (!this.screenshotData) {
      this.showError('스크린샷을 업로드해주세요.')
      return
    }
    
    if (!this.requestInputTarget.value.trim()) {
      this.showError('수정 요청을 입력해주세요.')
      return
    }

    // Show loading state
    this.showLoading()

    try {
      const response = await fetch(this.apiEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          file_id: this.fileId,
          screenshot: this.screenshotData,
          request: this.requestInputTarget.value,
          tier: this.getSelectedTier()
        })
      })

      const data = await response.json()

      if (data.success) {
        this.showResult(data.data)
      } else {
        // Handle specific error types
        let errorMessage = data.error || '수정 중 오류가 발생했습니다.'
        
        if (data.error_type === 'InsufficientCreditsError' && data.details) {
          errorMessage = `크레딧이 부족합니다. 필요 크레딧: ${data.details.required || 50}, 보유 크레딧: ${data.details.available || 0}`
        } else if (data.error_type === 'ValidationError') {
          // Check if it's a screenshot quality issue
          if (data.quality_feedback) {
            this.showQualityFeedback(errorMessage, data.quality_feedback)
            return
          } else if (data.details && data.details.errors) {
            errorMessage = data.details.errors.join(', ')
          }
        }
        
        this.showError(errorMessage)
      }
    } catch (error) {
      this.showError('네트워크 오류가 발생했습니다.')
    } finally {
      this.hideLoading()
    }
  }

  // Show loading state
  showLoading() {
    this.loadingStateTarget.classList.remove('hidden')
    this.submitButtonTarget.disabled = true
    this.errorMessageTarget.classList.add('hidden')
  }

  // Hide loading state
  hideLoading() {
    this.loadingStateTarget.classList.add('hidden')
    this.validateForm()
  }

  // Show result
  showResult(data) {
    this.resultSectionTarget.innerHTML = `
      <div class="bg-green-50 border border-green-200 rounded-lg p-6">
        <h3 class="text-lg font-semibold text-green-800 mb-4">✅ 수정 완료!</h3>
        
        <div class="space-y-4">
          <div class="bg-white rounded-lg p-4">
            <h4 class="font-medium text-gray-700 mb-2">수정된 파일</h4>
            <div class="flex items-center justify-between">
              <div>
                <p class="font-medium">${data.modified_file.filename}</p>
                <p class="text-sm text-gray-500">${this.formatFileSize(data.modified_file.size)}</p>
              </div>
              <a href="${data.download_url}" 
                 class="bg-blue-500 text-white px-4 py-2 rounded-lg hover:bg-blue-600 transition">
                다운로드
              </a>
            </div>
          </div>
          
          <div class="bg-white rounded-lg p-4">
            <h4 class="font-medium text-gray-700 mb-2">적용된 수정사항</h4>
            <ul class="space-y-2">
              ${data.modifications.map(mod => `
                <li class="flex items-start">
                  <span class="text-green-500 mr-2">•</span>
                  <div>
                    <span class="font-medium">${mod.cell}:</span>
                    <span class="text-gray-600">${mod.explanation}</span>
                  </div>
                </li>
              `).join('')}
            </ul>
          </div>
          
          <div class="text-sm text-gray-600">
            사용된 크레딧: ${data.credits_used}
          </div>
        </div>
      </div>
    `
    
    // Scroll to result
    this.resultSectionTarget.scrollIntoView({ behavior: 'smooth' })
  }

  // Show error
  showError(message) {
    this.errorMessageTarget.textContent = message
    this.errorMessageTarget.classList.remove('hidden')
  }

  // Format file size
  formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  // Get selected tier
  getSelectedTier() {
    const checkedInput = this.tierInputTargets.find(input => input.checked)
    return checkedInput ? checkedInput.value : 'balanced'
  }

  // Handle tier change
  tierChanged(event) {
    const tier = event.target.value
    console.log('Selected tier:', tier)
    
    // Update UI to show estimated credits
    this.updateEstimatedCredits(tier)
  }

  // Update estimated credits display
  updateEstimatedCredits(tier) {
    const credits = {
      speed: 30,
      balanced: 50,
      quality: 100
    }
    
    // You can add a visual indicator of estimated credits if needed
    console.log(`Estimated credits for ${tier}: ${credits[tier]}`)
  }

  // Show quality feedback for screenshots
  showQualityFeedback(errorMessage, feedback) {
    const { type, suggestion, tips } = feedback

    // Create quality feedback UI
    const feedbackHtml = `
      <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6">
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <svg class="h-6 w-6 text-yellow-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          </div>
          <div class="ml-3 flex-1">
            <h3 class="text-sm font-medium text-yellow-800">
              스크린샷 품질 개선이 필요합니다
            </h3>
            <div class="mt-2 text-sm text-yellow-700">
              <p class="mb-2">${suggestion}</p>
              <div class="mt-3">
                <p class="font-medium mb-1">💡 개선 방법:</p>
                <ul class="list-disc list-inside space-y-1">
                  ${tips.map(tip => `<li>${tip}</li>`).join('')}
                </ul>
              </div>
            </div>
            <div class="mt-4">
              <button type="button"
                      class="text-sm bg-yellow-100 hover:bg-yellow-200 text-yellow-800 font-medium py-2 px-4 rounded-md transition"
                      data-action="click->excel-modification#removeScreenshot">
                새 스크린샷 업로드
              </button>
            </div>
          </div>
        </div>
      </div>
    `

    this.errorMessageTarget.innerHTML = feedbackHtml
    this.errorMessageTarget.classList.remove('hidden')
    
    // Scroll to feedback
    this.errorMessageTarget.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }
}