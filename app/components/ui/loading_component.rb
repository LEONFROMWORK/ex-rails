# frozen_string_literal: true

class Ui::LoadingComponent < ViewComponent::Base
  attr_reader :size, :variant, :show_text, :text, :class_names

  def initialize(size: :md, variant: :spinner, show_text: true, text: nil, class: nil)
    @size = size
    @variant = variant
    @show_text = show_text
    @text = text || default_text
    @class_names = binding.local_variable_get(:class)
  end

  private

  def default_text
    case variant
    when :spinner
      "로딩 중..."
    when :pulse
      "처리 중..."
    when :dots
      "잠시만 기다려주세요..."
    else
      "로딩 중..."
    end
  end

  def size_classes
    case size
    when :sm
      "w-4 h-4"
    when :md
      "w-6 h-6"
    when :lg
      "w-8 h-8"
    when :xl
      "w-12 h-12"
    else
      "w-6 h-6"
    end
  end

  def spinner_classes
    base_classes = "inline-block animate-spin rounded-full border-2 border-solid"
    color_classes = "border-current border-r-transparent"
    [ base_classes, color_classes, size_classes ].join(" ")
  end

  def pulse_classes
    base_classes = "inline-block rounded-full animate-pulse"
    color_classes = "bg-current"
    [ base_classes, color_classes, size_classes ].join(" ")
  end

  def dots_classes
    "flex space-x-1"
  end

  def dot_classes
    base_classes = "rounded-full animate-bounce"
    color_classes = "bg-current"
    size_class = case size
    when :sm then "w-1 h-1"
    when :md then "w-1.5 h-1.5"
    when :lg then "w-2 h-2"
    when :xl then "w-3 h-3"
    else "w-1.5 h-1.5"
    end
    [ base_classes, color_classes, size_class ].join(" ")
  end

  def text_classes
    case size
    when :sm
      "text-xs"
    when :md
      "text-sm"
    when :lg
      "text-base"
    when :xl
      "text-lg"
    else
      "text-sm"
    end
  end

  def container_classes
    base = "inline-flex items-center space-x-2"
    [ base, class_names ].compact.join(" ")
  end
end
