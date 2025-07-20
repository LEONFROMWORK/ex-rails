module Ui
  class AlertDialogComponent < ViewComponent::Base
    def initialize(title:, description:, cancel_text: "취소", confirm_text: "확인", variant: "default", **attrs)
      @title = title
      @description = description
      @cancel_text = cancel_text
      @confirm_text = confirm_text
      @variant = variant
      @attrs = attrs
    end

    private

    attr_reader :title, :description, :cancel_text, :confirm_text, :variant, :attrs

    def overlay_classes
      "fixed inset-0 z-50 bg-background/80 backdrop-blur-sm"
    end

    def dialog_classes
      [
        "fixed left-[50%] top-[50%] z-50 grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 border bg-background p-6 shadow-lg duration-200",
        "sm:rounded-lg",
        attrs[:class]
      ].compact.join(" ")
    end

    def confirm_button_variant
      case variant
      when "destructive"
        "destructive"
      else
        "default"
      end
    end
  end
end
