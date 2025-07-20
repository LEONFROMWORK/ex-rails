import { Controller } from "@hotwired/stimulus"

// shadcn/ui 스타일의 탭 컨트롤러
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // 초기 활성 탭 설정
    const activeTab = this.tabTargets.find(tab => tab.getAttribute("aria-selected") === "true")
    if (activeTab) {
      this.showPanel(activeTab.dataset.tabPanel)
    }
  }

  switch(event) {
    event.preventDefault()
    const tab = event.currentTarget
    const panelId = tab.dataset.tabPanel

    // 모든 탭 비활성화
    this.tabTargets.forEach(t => {
      t.setAttribute("aria-selected", "false")
      t.classList.remove("bg-background", "text-foreground", "shadow-sm")
      t.classList.add("hover:bg-background/50")
    })

    // 클릭된 탭 활성화
    tab.setAttribute("aria-selected", "true")
    tab.classList.add("bg-background", "text-foreground", "shadow-sm")
    tab.classList.remove("hover:bg-background/50")

    // 패널 전환
    this.showPanel(panelId)
  }

  showPanel(panelId) {
    // 모든 패널 숨기기
    this.panelTargets.forEach(panel => {
      panel.classList.add("hidden")
      panel.setAttribute("aria-hidden", "true")
    })

    // 선택된 패널 표시
    const selectedPanel = this.panelTargets.find(panel => panel.id === panelId)
    if (selectedPanel) {
      selectedPanel.classList.remove("hidden")
      selectedPanel.setAttribute("aria-hidden", "false")
    }
  }

  // 키보드 네비게이션 지원
  handleKeydown(event) {
    const currentTab = event.currentTarget
    const tabs = this.tabTargets
    const currentIndex = tabs.indexOf(currentTab)
    let newIndex

    switch (event.key) {
      case "ArrowLeft":
        event.preventDefault()
        newIndex = currentIndex === 0 ? tabs.length - 1 : currentIndex - 1
        tabs[newIndex].click()
        tabs[newIndex].focus()
        break
      case "ArrowRight":
        event.preventDefault()
        newIndex = currentIndex === tabs.length - 1 ? 0 : currentIndex + 1
        tabs[newIndex].click()
        tabs[newIndex].focus()
        break
      case "Home":
        event.preventDefault()
        tabs[0].click()
        tabs[0].focus()
        break
      case "End":
        event.preventDefault()
        tabs[tabs.length - 1].click()
        tabs[tabs.length - 1].focus()
        break
    }
  }
}