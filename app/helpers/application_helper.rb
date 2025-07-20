module ApplicationHelper
  # shadcn/ui 컴포넌트 헬퍼 메서드

  def render_button(text = nil, **options, &block)
    render Ui::ButtonComponent.new(**options) do
      text || capture(&block)
    end
  end

  def render_card(**options, &block)
    render Ui::CardComponent.new(**options), &block
  end

  def render_badge(text = nil, **options, &block)
    render Ui::BadgeComponent.new(**options) do
      text || capture(&block)
    end
  end

  def render_alert(**options, &block)
    render Ui::AlertComponent.new(**options), &block
  end

  def render_input(**options)
    render Ui::InputComponent.new(**options)
  end

  def render_select(**options)
    render Ui::SelectComponent.new(**options)
  end

  # 색상 시스템 헬퍼
  def primary_button_classes
    "bg-primary text-primary-foreground hover:bg-primary/90"
  end

  def secondary_button_classes
    "bg-secondary text-secondary-foreground hover:bg-secondary/80"
  end

  def destructive_button_classes
    "bg-destructive text-destructive-foreground hover:bg-destructive/90"
  end

  # 기존 헬퍼 메서드와의 호환성을 위한 래퍼
  def button_to_shadcn(text, url, **options)
    method = options.delete(:method) || :post
    button_options = options.except(:class, :data, :form)

    button_to url, method: method, **options.slice(:data, :form) do
      render_button(text, **button_options)
    end
  end

  def link_to_shadcn(text, url, **options)
    button_options = options.except(:class, :data)

    link_to url, **options.slice(:data) do
      render_button(text, **button_options.merge(as: :span))
    end
  end

  # 다크 모드 토글 헬퍼
  def theme_toggle_button
    render Ui::ThemeToggleComponent.new
  end

  # Flash 메시지 헬퍼
  def render_flash_messages
    flash.map do |type, message|
      variant = case type.to_s
      when "notice", "success"
        :success
      when "alert", "error"
        :destructive
      when "warning"
        :warning
      else
        :default
      end

      render_alert(variant: variant, dismissible: true) do
        message
      end
    end.join.html_safe
  end

  # 탭 시스템 헬퍼
  def render_tabs(&block)
    content_tag :div, class: "w-full", data: { controller: "tabs" }, &block
  end

  def tab_list(&block)
    content_tag :div, class: "inline-flex h-10 items-center justify-center rounded-md bg-muted p-1 text-muted-foreground", role: "tablist", &block
  end

  def tab(text, id:, active: false, &block)
    classes = [
      "inline-flex items-center justify-center whitespace-nowrap rounded-sm px-3 py-1.5 text-sm font-medium ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
      active ? "bg-background text-foreground shadow-sm" : "hover:bg-background/50"
    ].join(" ")

    content_tag :button,
                type: "button",
                class: classes,
                role: "tab",
                "aria-selected": active,
                "aria-controls": "#{id}-panel",
                data: {
                  tabs_target: "tab",
                  tab_panel: "#{id}-panel",
                  action: "click->tabs#switch"
                } do
      block_given? ? capture(&block) : text
    end
  end

  def tab_panels(&block)
    content_tag :div, class: "mt-2", &block
  end

  def tab_panel(id:, active: false, &block)
    content_tag :div,
                id: "#{id}-panel",
                role: "tabpanel",
                class: active ? "" : "hidden",
                data: { tabs_target: "panel" },
                &block
  end

  # 통일된 스타일 클래스
  def card_classes(custom_classes = nil)
    [ "rounded-lg border bg-card text-card-foreground shadow-sm", custom_classes ].compact.join(" ")
  end

  def input_classes(custom_classes = nil)
    [ "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50", custom_classes ].compact.join(" ")
  end
end
