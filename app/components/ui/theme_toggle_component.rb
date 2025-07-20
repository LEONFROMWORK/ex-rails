# frozen_string_literal: true

class Ui::ThemeToggleComponent < ViewComponent::Base
  def initialize(size: :md, show_label: true, position: :right)
    @size = size
    @show_label = show_label
    @position = position
  end

  private

  attr_reader :size, :show_label, :position

  def toggle_classes
    base_classes = "relative inline-flex items-center rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"

    size_classes = case size
    when :sm
      "h-5 w-9"
    when :lg
      "h-7 w-12"
    else # :md
      "h-6 w-11"
    end

    "#{base_classes} #{size_classes}"
  end

  def switch_classes
    base_classes = "pointer-events-none inline-block transform rounded-full bg-white shadow-lg ring-0 transition duration-200 ease-in-out dark:bg-gray-200"

    size_classes = case size
    when :sm
      "h-4 w-4"
    when :lg
      "h-6 w-6"
    else # :md
      "h-5 w-5"
    end

    "#{base_classes} #{size_classes}"
  end

  def icon_classes
    case size
    when :sm
      "h-3 w-3"
    when :lg
      "h-4 w-4"
    else # :md
      "h-3.5 w-3.5"
    end
  end

  def label_classes
    case size
    when :sm
      "text-xs"
    when :lg
      "text-base"
    else # :md
      "text-sm"
    end
  end

  def container_classes
    base_classes = "flex items-center gap-3"
    direction_class = position == :left ? "flex-row" : "flex-row-reverse"
    "#{base_classes} #{direction_class}"
  end
end
