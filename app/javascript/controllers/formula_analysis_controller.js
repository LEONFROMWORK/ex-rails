import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

// FormulaEngine 분석 결과를 관리하고 표시하는 Stimulus 컨트롤러
export default class extends Controller {
  static targets = [
    "complexityScore", "complexityLevel", "formulaCount", "functionCount",
    "functionChart", "functionTable", "dependencyChart", "circularRefList",
    "errorsList", "optimizationList", "filterForm", "sortSelect"
  ]
  
  static values = {
    fileId: Number,
    analysisData: Object,
    chartTheme: String
  }

  connect() {
    console.log("Formula Analysis controller connected")
    this.setupChartTheme()
    this.initializeCharts()
    this.setupEventListeners()
  }

  disconnect() {
    this.destroyCharts()
  }

  // 차트 테마 설정
  setupChartTheme() {
    this.chartColors = this.chartThemeValue === 'dark' ? {
      primary: '#3b82f6',
      secondary: '#10b981',
      accent: '#f59e0b',
      danger: '#ef4444',
      text: '#f9fafb',
      grid: '#374151'
    } : {
      primary: '#3b82f6',
      secondary: '#10b981', 
      accent: '#f59e0b',
      danger: '#ef4444',
      text: '#1f2937',
      grid: '#e5e7eb'
    }
  }

  // 이벤트 리스너 설정
  setupEventListeners() {
    if (this.hasSortSelectTarget) {
      this.sortSelectTarget.addEventListener('change', this.handleSortChange.bind(this))
    }

    if (this.hasFilterFormTarget) {
      this.filterFormTarget.addEventListener('submit', this.handleFilterSubmit.bind(this))
    }

    // 키보드 단축키
    document.addEventListener('keydown', this.handleKeyboardShortcuts.bind(this))
  }

  // 분석 데이터 업데이트
  analysisDataValueChanged() {
    if (this.analysisDataValue && Object.keys(this.analysisDataValue).length > 0) {
      this.updateAllComponents()
    }
  }

  // 모든 컴포넌트 업데이트
  updateAllComponents() {
    this.updateComplexityDisplay()
    this.updateFormulaStats()
    this.updateFunctionAnalysis()
    this.updateDependencyAnalysis()
    this.updateCircularReferences()
    this.updateFormulaErrors()
    this.updateOptimizationSuggestions()
  }

  // === 복잡도 표시 업데이트 ===
  updateComplexityDisplay() {
    const complexity = this.analysisDataValue.formula_complexity_score || 0
    const level = this.analysisDataValue.formula_complexity_level || 'Unknown'

    if (this.hasComplexityScoreTarget) {
      this.complexityScoreTarget.textContent = complexity.toFixed(2)
      this.animateNumber(this.complexityScoreTarget, 0, complexity, 1000)
    }

    if (this.hasComplexityLevelTarget) {
      this.complexityLevelTarget.textContent = level
      this.complexityLevelTarget.className = this.getComplexityLevelClass(level)
    }
  }

  // 복잡도 레벨에 따른 CSS 클래스 반환
  getComplexityLevelClass(level) {
    const baseClasses = "px-3 py-1 rounded-full text-sm font-medium"
    
    switch (level.toLowerCase()) {
      case 'low':
        return `${baseClasses} bg-green-100 text-green-800`
      case 'medium':
        return `${baseClasses} bg-yellow-100 text-yellow-800`
      case 'high':
        return `${baseClasses} bg-orange-100 text-orange-800`
      case 'very high':
        return `${baseClasses} bg-red-100 text-red-800`
      default:
        return `${baseClasses} bg-gray-100 text-gray-800`
    }
  }

  // === 수식 통계 업데이트 ===
  updateFormulaStats() {
    const formulaCount = this.analysisDataValue.formula_count || 0
    const functionStats = this.analysisDataValue.formula_functions || {}
    const totalFunctions = functionStats.total_functions || 0

    if (this.hasFormulaCountTarget) {
      this.formulaCountTarget.textContent = formulaCount.toLocaleString()
      this.animateNumber(this.formulaCountTarget, 0, formulaCount, 1000)
    }

    if (this.hasFunctionCountTarget) {
      this.functionCountTarget.textContent = totalFunctions.toLocaleString()
      this.animateNumber(this.functionCountTarget, 0, totalFunctions, 1000)
    }
  }

  // === 함수 분석 업데이트 ===
  updateFunctionAnalysis() {
    const functionStats = this.analysisDataValue.formula_functions || {}
    
    this.updateFunctionChart(functionStats)
    this.updateFunctionTable(functionStats)
  }

  // 함수 사용 차트 업데이트
  updateFunctionChart(functionStats) {
    if (!this.hasFunctionChartTarget) return

    const categories = functionStats.categories || {}
    const labels = Object.keys(categories)
    const data = labels.map(label => categories[label].count || 0)

    this.destroyChart('functionChart')

    const ctx = this.functionChartTarget.getContext('2d')
    this.functionChart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: labels,
        datasets: [{
          data: data,
          backgroundColor: [
            this.chartColors.primary,
            this.chartColors.secondary,
            this.chartColors.accent,
            this.chartColors.danger,
            '#8b5cf6',
            '#06b6d4',
            '#84cc16',
            '#f97316'
          ],
          borderWidth: 2,
          borderColor: '#ffffff'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              padding: 20,
              usePointStyle: true,
              color: this.chartColors.text
            }
          },
          tooltip: {
            callbacks: {
              label: (context) => {
                const label = context.label || ''
                const value = context.parsed || 0
                const total = context.dataset.data.reduce((a, b) => a + b, 0)
                const percentage = ((value / total) * 100).toFixed(1)
                return `${label}: ${value} (${percentage}%)`
              }
            }
          }
        }
      }
    })
  }

  // 함수 사용 테이블 업데이트
  updateFunctionTable(functionStats) {
    if (!this.hasFunctionTableTarget) return

    const functionUsage = functionStats.function_usage || []
    const sortedFunctions = functionUsage
      .sort((a, b) => (b.count || 0) - (a.count || 0))
      .slice(0, 10) // 상위 10개만 표시

    const tableHTML = `
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Function
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Usage Count
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Category
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            ${sortedFunctions.map((func, index) => `
              <tr class="hover:bg-gray-50 transition-colors">
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <span class="text-sm font-mono font-medium text-gray-900">
                      ${func.name || 'Unknown'}
                    </span>
                    <span class="ml-2 text-xs text-gray-500">#${index + 1}</span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class="text-sm text-gray-900">${(func.count || 0).toLocaleString()}</span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class="inline-flex px-2 py-1 text-xs font-medium rounded-full ${this.getCategoryBadgeClass(func.category)}">
                    ${func.category || 'Other'}
                  </span>
                </td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `

    this.functionTableTarget.innerHTML = tableHTML
  }

  // 함수 카테고리 배지 클래스 반환
  getCategoryBadgeClass(category) {
    switch (category?.toLowerCase()) {
      case 'statistical':
        return 'bg-blue-100 text-blue-800'
      case 'logical':
        return 'bg-purple-100 text-purple-800'
      case 'lookup':
        return 'bg-green-100 text-green-800'
      case 'text':
        return 'bg-yellow-100 text-yellow-800'
      case 'date & time':
        return 'bg-indigo-100 text-indigo-800'
      case 'math':
        return 'bg-red-100 text-red-800'
      default:
        return 'bg-gray-100 text-gray-800'
    }
  }

  // === 의존성 분석 업데이트 ===
  updateDependencyAnalysis() {
    if (!this.hasDependencyChartTarget) return

    const dependencies = this.analysisDataValue.formula_dependencies || {}
    const directDeps = dependencies.direct_dependencies || []
    const indirectDeps = dependencies.indirect_dependencies || []

    const data = {
      labels: ['Direct Dependencies', 'Indirect Dependencies'],
      datasets: [{
        data: [directDeps.length, indirectDeps.length],
        backgroundColor: [this.chartColors.primary, this.chartColors.secondary],
        borderWidth: 2,
        borderColor: '#ffffff'
      }]
    }

    this.destroyChart('dependencyChart')

    const ctx = this.dependencyChartTarget.getContext('2d')
    this.dependencyChart = new Chart(ctx, {
      type: 'pie',
      data: data,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              color: this.chartColors.text
            }
          }
        }
      }
    })
  }

  // === 순환 참조 업데이트 ===
  updateCircularReferences() {
    if (!this.hasCircularRefListTarget) return

    const circularRefs = this.analysisDataValue.circular_references || []

    if (circularRefs.length === 0) {
      this.circularRefListTarget.innerHTML = `
        <div class="text-center py-8">
          <div class="w-16 h-16 mx-auto mb-4 flex items-center justify-center bg-green-100 rounded-full">
            <i class="fas fa-check-circle text-2xl text-green-600"></i>
          </div>
          <h3 class="text-lg font-medium text-gray-900 mb-2">No Circular References</h3>
          <p class="text-gray-500">Great! No circular references were detected in your formulas.</p>
        </div>
      `
      return
    }

    const listHTML = circularRefs.map((ref, index) => `
      <div class="border border-red-200 rounded-lg p-4 mb-4 bg-red-50">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <div class="flex items-center mb-2">
              <i class="fas fa-exclamation-triangle text-red-500 mr-2"></i>
              <h4 class="text-lg font-medium text-red-900">Circular Reference #${index + 1}</h4>
              <span class="ml-2 px-2 py-1 text-xs font-medium rounded-full ${this.getSeverityBadgeClass(ref.severity)}">
                ${ref.severity || 'Medium'}
              </span>
            </div>
            <p class="text-red-800 mb-3">${ref.description || 'Circular reference detected'}</p>
            <div class="text-sm text-red-700">
              <strong>Affected cells:</strong> ${(ref.cells || []).join(' → ')}
            </div>
            ${ref.chain && ref.chain.length > 0 ? `
              <div class="text-sm text-red-700 mt-1">
                <strong>Reference chain:</strong> ${ref.chain.join(' → ')}
              </div>
            ` : ''}
          </div>
        </div>
      </div>
    `).join('')

    this.circularRefListTarget.innerHTML = listHTML
  }

  // === 수식 오류 업데이트 ===
  updateFormulaErrors() {
    if (!this.hasErrorsListTarget) return

    const formulaErrors = this.analysisDataValue.formula_errors || []

    if (formulaErrors.length === 0) {
      this.errorsListTarget.innerHTML = `
        <div class="text-center py-8">
          <div class="w-16 h-16 mx-auto mb-4 flex items-center justify-center bg-green-100 rounded-full">
            <i class="fas fa-shield-check text-2xl text-green-600"></i>
          </div>
          <h3 class="text-lg font-medium text-gray-900 mb-2">No Formula Errors</h3>
          <p class="text-gray-500">Excellent! All formulas appear to be error-free.</p>
        </div>
      `
      return
    }

    const listHTML = formulaErrors.map((error, index) => `
      <div class="border border-red-200 rounded-lg p-4 mb-4 hover:shadow-md transition-shadow">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <div class="flex items-center mb-2">
              <span class="px-2 py-1 text-xs font-medium rounded-full bg-red-100 text-red-800">
                ${error.error_type || 'Error'}
              </span>
              <span class="ml-2 text-sm text-gray-500">
                <i class="fas fa-map-marker-alt mr-1"></i>
                ${error.cell || 'Unknown cell'}
              </span>
              <span class="ml-auto px-2 py-1 text-xs font-medium rounded-full ${this.getSeverityBadgeClass(error.severity)}">
                ${error.severity || 'Medium'}
              </span>
            </div>
            <p class="text-gray-900 font-medium mb-2">${error.message || 'Formula error detected'}</p>
            ${error.formula ? `
              <div class="bg-gray-100 p-2 rounded text-sm font-mono text-gray-800 mb-2">
                ${error.formula}
              </div>
            ` : ''}
            ${error.suggestion ? `
              <div class="text-sm text-blue-700 bg-blue-50 p-2 rounded">
                <i class="fas fa-lightbulb mr-1"></i>
                <strong>Suggestion:</strong> ${error.suggestion}
              </div>
            ` : ''}
          </div>
        </div>
      </div>
    `).join('')

    this.errorsListTarget.innerHTML = listHTML
  }

  // === 최적화 제안 업데이트 ===
  updateOptimizationSuggestions() {
    if (!this.hasOptimizationListTarget) return

    const suggestions = this.analysisDataValue.formula_optimization_suggestions || []

    if (suggestions.length === 0) {
      this.optimizationListTarget.innerHTML = `
        <div class="text-center py-8">
          <div class="w-16 h-16 mx-auto mb-4 flex items-center justify-center bg-blue-100 rounded-full">
            <i class="fas fa-thumbs-up text-2xl text-blue-600"></i>
          </div>
          <h3 class="text-lg font-medium text-gray-900 mb-2">Well Optimized</h3>
          <p class="text-gray-500">Your formulas are already well-optimized. No suggestions at this time.</p>
        </div>
      `
      return
    }

    const groupedSuggestions = this.groupSuggestionsByType(suggestions)

    const listHTML = Object.entries(groupedSuggestions).map(([type, typeSuggestions]) => `
      <div class="mb-6">
        <h4 class="text-lg font-medium text-gray-900 mb-3 capitalize">
          ${type.replace(/_/g, ' ')} Suggestions
        </h4>
        ${typeSuggestions.map((suggestion, index) => `
          <div class="border border-gray-200 rounded-lg p-4 mb-3 hover:shadow-md transition-shadow">
            <div class="flex items-start justify-between mb-2">
              <div class="flex items-center">
                <span class="px-2 py-1 text-xs font-medium rounded-full ${this.getPriorityBadgeClass(suggestion.priority)}">
                  ${suggestion.priority || 'Medium'} Priority
                </span>
                <span class="ml-2 text-sm text-gray-500">
                  <i class="fas fa-map-marker-alt mr-1"></i>
                  ${suggestion.cell || 'Multiple cells'}
                </span>
              </div>
            </div>
            <p class="text-gray-900 font-medium mb-2">${suggestion.issue || 'Optimization opportunity'}</p>
            <p class="text-gray-700 mb-3">${suggestion.suggestion || 'Consider optimizing this formula'}</p>
            ${suggestion.current_formula ? `
              <div class="bg-gray-100 p-2 rounded text-sm font-mono text-gray-800">
                <strong>Current:</strong> ${suggestion.current_formula}
              </div>
            ` : ''}
          </div>
        `).join('')}
      </div>
    `).join('')

    this.optimizationListTarget.innerHTML = listHTML
  }

  // === 유틸리티 메소드 ===

  // 제안사항을 타입별로 그룹화
  groupSuggestionsByType(suggestions) {
    return suggestions.reduce((groups, suggestion) => {
      const type = suggestion.type || 'other'
      if (!groups[type]) {
        groups[type] = []
      }
      groups[type].push(suggestion)
      return groups
    }, {})
  }

  // 심각도 배지 클래스 반환
  getSeverityBadgeClass(severity) {
    switch (severity?.toLowerCase()) {
      case 'low':
        return 'bg-green-100 text-green-800'
      case 'medium':
        return 'bg-yellow-100 text-yellow-800'
      case 'high':
        return 'bg-red-100 text-red-800'
      default:
        return 'bg-gray-100 text-gray-800'
    }
  }

  // 우선순위 배지 클래스 반환
  getPriorityBadgeClass(priority) {
    switch (priority?.toLowerCase()) {
      case 'low':
        return 'bg-blue-100 text-blue-800'
      case 'medium':
        return 'bg-yellow-100 text-yellow-800'
      case 'high':
        return 'bg-red-100 text-red-800'
      default:
        return 'bg-gray-100 text-gray-800'
    }
  }

  // 숫자 애니메이션
  animateNumber(element, start, end, duration) {
    const startTime = performance.now()
    const range = end - start

    const updateNumber = (currentTime) => {
      const elapsed = currentTime - startTime
      const progress = Math.min(elapsed / duration, 1)
      
      const current = start + (range * this.easeOutQuart(progress))
      element.textContent = Math.round(current).toLocaleString()

      if (progress < 1) {
        requestAnimationFrame(updateNumber)
      }
    }

    requestAnimationFrame(updateNumber)
  }

  // 이징 함수
  easeOutQuart(t) {
    return 1 - Math.pow(1 - t, 4)
  }

  // 차트 초기화
  initializeCharts() {
    this.charts = {}
  }

  // 특정 차트 제거
  destroyChart(chartName) {
    if (this[chartName]) {
      this[chartName].destroy()
      this[chartName] = null
    }
  }

  // 모든 차트 제거
  destroyCharts() {
    if (this.functionChart) {
      this.functionChart.destroy()
    }
    if (this.dependencyChart) {
      this.dependencyChart.destroy()
    }
  }

  // === 이벤트 핸들러 ===

  // 정렬 변경 처리
  handleSortChange(event) {
    const sortBy = event.target.value
    this.sortAnalysisResults(sortBy)
  }

  // 필터 제출 처리
  handleFilterSubmit(event) {
    event.preventDefault()
    const formData = new FormData(event.target)
    this.filterAnalysisResults(formData)
  }

  // 키보드 단축키 처리
  handleKeyboardShortcuts(event) {
    if (event.ctrlKey || event.metaKey) {
      switch (event.key) {
        case 'f':
          event.preventDefault()
          this.focusFilterInput()
          break
        case 'r':
          event.preventDefault()
          this.refreshAnalysis()
          break
      }
    }
  }

  // === 액션 메소드 ===

  // 분석 결과 정렬
  sortAnalysisResults(sortBy) {
    // 구현 필요: 정렬 로직
    console.log('Sorting by:', sortBy)
  }

  // 분석 결과 필터링
  filterAnalysisResults(formData) {
    // 구현 필요: 필터링 로직
    console.log('Filtering with:', Object.fromEntries(formData))
  }

  // 필터 입력란에 포커스
  focusFilterInput() {
    const filterInput = this.element.querySelector('input[type="search"]')
    if (filterInput) {
      filterInput.focus()
    }
  }

  // 분석 새로고침
  refreshAnalysis() {
    if (this.fileIdValue) {
      window.location.reload()
    }
  }

  // 분석 데이터 내보내기
  exportAnalysisData() {
    if (this.analysisDataValue) {
      const dataStr = JSON.stringify(this.analysisDataValue, null, 2)
      const blob = new Blob([dataStr], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      
      const a = document.createElement('a')
      a.href = url
      a.download = `formula-analysis-${this.fileIdValue}.json`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
    }
  }
}