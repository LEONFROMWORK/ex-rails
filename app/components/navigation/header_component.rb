# frozen_string_literal: true

class Navigation::HeaderComponent < ViewComponent::Base
  def initialize(current_user:, current_path:)
    @current_user = current_user
    @current_path = current_path
  end

  private

  attr_reader :current_user, :current_path

  def breadcrumbs
    return [] if current_path == "/"

    path_segments = current_path.split("/").reject(&:empty?)
    breadcrumb_items = []

    case path_segments.first
    when "excel_files"
      breadcrumb_items << { name: I18n.t("navigation.files"), path: excel_files_path }
      if path_segments.second == "new"
        breadcrumb_items << { name: I18n.t("navigation.upload"), path: nil }
      elsif path_segments.second && path_segments.second != "new"
        breadcrumb_items << { name: I18n.t("navigation.analysis"), path: nil }
      end
    when "chat_conversations"
      breadcrumb_items << { name: I18n.t("navigation.chat"), path: chat_conversations_path }
    when "analytics"
      breadcrumb_items << { name: I18n.t("navigation.analytics"), path: analytics_path }
    when "admin"
      breadcrumb_items << { name: I18n.t("navigation.admin"), path: admin_root_path }
      case path_segments.second
      when "users"
        breadcrumb_items << { name: I18n.t("navigation.users"), path: admin_users_path }
      when "analyses"
        breadcrumb_items << { name: I18n.t("navigation.analyses"), path: admin_analyses_path }
      when "ai_cache"
        breadcrumb_items << { name: I18n.t("navigation.ai_cache"), path: admin_ai_cache_index_path }
      when "stats"
        breadcrumb_items << { name: I18n.t("navigation.stats"), path: admin_stats_path }
      end
    when "profile"
      breadcrumb_items << { name: I18n.t("navigation.profile"), path: profile_path }
    when "settings"
      breadcrumb_items << { name: I18n.t("navigation.settings"), path: settings_path }
    end

    breadcrumb_items
  end

  def page_title
    case current_path
    when "/"
      I18n.t("navigation.dashboard")
    when excel_files_path
      I18n.t("navigation.files")
    when chat_conversations_path
      I18n.t("navigation.chat")
    when analytics_path
      I18n.t("navigation.analytics")
    when admin_root_path
      I18n.t("navigation.admin_dashboard")
    when profile_path
      I18n.t("navigation.profile")
    when settings_path
      I18n.t("navigation.settings")
    else
      breadcrumbs.last&.dig(:name) || I18n.t("common.app_name")
    end
  end

  def icon_svg(icon_name, classes = "w-5 h-5")
    icons = {
      "menu" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/></svg>',
      "chevron-right" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>',
      "bell" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/></svg>',
      "search" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>'
    }

    icons[icon_name]&.html_safe || ""
  end

  # Placeholder methods for routes
  def analytics_path
    "/analytics"
  end

  def profile_path
    "/profile"
  end

  def settings_path
    "/settings"
  end
end
