# frozen_string_literal: true

class Navigation::RightSidebarComponent < ViewComponent::Base
  def initialize(current_user:, current_path:)
    @current_user = current_user
    @current_path = current_path
  end

  private

  attr_reader :current_user, :current_path

  def navigation_items
    [
      {
        name: "대시보드",
        path: root_path,
        icon: "home",
        active: current_path == root_path
      },
      {
        name: "엑셀 분석",
        path: excel_files_path,
        icon: "file-spreadsheet",
        active: current_path.start_with?("/excel_files")
      },
      {
        name: "AI 채팅",
        path: chat_conversations_path,
        icon: "message-circle",
        active: current_path.start_with?("/chat_conversations")
      },
      {
        name: "분석 결과",
        path: analytics_path,
        icon: "chart-bar",
        active: current_path.start_with?("/analytics")
      }
    ]
  end

  def user_menu_items
    [
      {
        name: "프로필",
        path: profile_path,
        icon: "user"
      },
      {
        name: "설정",
        path: settings_path,
        icon: "settings"
      }
    ]
  end
end
