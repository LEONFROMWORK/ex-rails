# frozen_string_literal: true

class Ui::AlertComponent < ViewComponent::Base
  VARIANTS = {
    default: "border-border text-foreground",
    destructive: "border-destructive/50 text-destructive dark:border-destructive",
    success: "border-green-500/50 text-green-600 dark:border-green-500",
    warning: "border-yellow-500/50 text-yellow-600 dark:border-yellow-500",
    info: "border-blue-500/50 text-blue-600 dark:border-blue-500"
  }.freeze

  def initialize(variant: :default, dismissible: false, **options)
    @variant = variant
    @dismissible = dismissible
    @options = options
  end

  private

  attr_reader :variant, :dismissible, :options

  def alert_classes
    [
      "relative w-full rounded-lg border p-4",
      "[&>svg~*]:pl-7 [&>svg+div]:translate-y-[-3px] [&>svg]:absolute [&>svg]:left-4 [&>svg]:top-4 [&>svg]:text-foreground",
      VARIANTS[variant],
      options[:class]
    ].compact.join(" ")
  end

  def icon_svg
    case variant
    when :success
      success_icon
    when :warning
      warning_icon
    when :destructive
      error_icon
    when :info
      info_icon
    else
      info_icon
    end
  end

  def success_icon
    <<~SVG.html_safe
      <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
      </svg>
    SVG
  end

  def warning_icon
    <<~SVG.html_safe
      <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
      </svg>
    SVG
  end

  def error_icon
    <<~SVG.html_safe
      <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
      </svg>
    SVG
  end

  def info_icon
    <<~SVG.html_safe
      <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
    SVG
  end
end
