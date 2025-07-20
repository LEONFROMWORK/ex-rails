# frozen_string_literal: true

class Navigation::SidebarComponent < ViewComponent::Base
  def initialize(current_user:, current_path:)
    @current_user = current_user
    @current_path = current_path
  end

  private

  attr_reader :current_user, :current_path

  def navigation_items
    items = [
      {
        name: I18n.t("navigation.dashboard"),
        path: root_path,
        icon: "home",
        active: current_path == root_path
      },
      {
        name: I18n.t("navigation.files"),
        path: excel_files_path,
        icon: "file-text",
        active: current_path.start_with?("/excel_files"),
        badge: recent_files_count
      },
      {
        name: I18n.t("navigation.chat"),
        path: chat_conversations_path,
        icon: "message-circle",
        active: current_path.start_with?("/chat_conversations"),
        badge: unread_messages_count
      },
      {
        name: I18n.t("navigation.analytics"),
        path: analytics_path,
        icon: "bar-chart-3",
        active: current_path.start_with?("/analytics")
      }
    ]

    # Add admin items if user is admin
    if current_user.can_access_admin?
      items += [
        {
          name: I18n.t("navigation.admin"),
          path: admin_root_path,
          icon: "shield",
          active: current_path.start_with?("/admin"),
          submenu: admin_submenu_items
        }
      ]
    end

    items
  end

  def admin_submenu_items
    [
      {
        name: I18n.t("navigation.dashboard"),
        path: admin_root_path,
        icon: "layout-dashboard",
        active: current_path == admin_root_path
      },
      {
        name: I18n.t("navigation.users"),
        path: admin_users_path,
        icon: "users",
        active: current_path.start_with?("/admin/users")
      },
      {
        name: I18n.t("navigation.analyses"),
        path: admin_analyses_path,
        icon: "activity",
        active: current_path.start_with?("/admin/analyses")
      },
      {
        name: I18n.t("navigation.ai_cache"),
        path: admin_ai_cache_index_path,
        icon: "database",
        active: current_path.start_with?("/admin/ai_cache")
      },
      {
        name: I18n.t("navigation.stats"),
        path: admin_stats_path,
        icon: "trending-up",
        active: current_path.start_with?("/admin/stats")
      }
    ]
  end

  def user_menu_items
    items = [
      {
        name: I18n.t("navigation.profile"),
        path: profile_path,
        icon: "user"
      },
      {
        name: I18n.t("navigation.settings"),
        path: settings_path,
        icon: "settings"
      }
    ]

    # Add billing menu only if payment is enabled
    if Rails.application.config.features[:payment_enabled]
      items << {
        name: I18n.t("navigation.billing"),
        path: subscriptions_path,
        icon: "credit-card"
      }
    end

    items << {
      name: I18n.t("navigation.api_keys"),
      path: api_keys_path,
      icon: "key"
    }

    items
  end

  def recent_files_count
    return nil unless current_user.excel_files.recent.limit(5).count > 0

    current_user.excel_files.recent.limit(5).count
  end

  def unread_messages_count
    # This would be implemented based on your chat message read tracking
    # For now, return nil to hide badge
    nil
  end

  def icon_svg(icon_name, classes = "w-5 h-5")
    # Using Lucide icons (compatible with shadcn/ui)
    icons = {
      "home" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"/></svg>',
      "file-text" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>',
      "message-circle" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/></svg>',
      "bar-chart-3" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/></svg>',
      "shield" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/></svg>',
      "layout-dashboard" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/></svg>',
      "users" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a4 4 0 11-8 0 4 4 0 018 0z"/></svg>',
      "activity" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/></svg>',
      "database" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4"/></svg>',
      "trending-up" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"/></svg>',
      "user" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>',
      "settings" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>',
      "credit-card" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"/></svg>',
      "key" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"/></svg>',
      "menu" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/></svg>',
      "x" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>',
      "chevron-down" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>',
      "log-out" => '<svg class="' + classes + '" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"/></svg>'
    }

    icons[icon_name]&.html_safe || ""
  end

  # Placeholder paths - these should be implemented in routes
  def analytics_path
    "/analytics"
  end

  def profile_path
    "/profile"
  end

  def settings_path
    "/settings"
  end

  def api_keys_path
    "/api_keys"
  end
end
