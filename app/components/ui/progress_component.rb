# frozen_string_literal: true

class Ui::ProgressComponent < ViewComponent::Base
  def initialize(value: 0, max: 100, label: nil, **options)
    @value = value
    @max = max
    @label = label
    @options = options
  end

  private

  attr_reader :value, :max, :label, :options

  def progress_percentage
    return 0 if max == 0
    (value.to_f / max.to_f * 100).round(2)
  end

  def progress_classes
    [
      "relative h-4 w-full overflow-hidden rounded-full bg-secondary",
      options[:class]
    ].compact.join(" ")
  end

  def progress_bar_classes
    [
      "h-full w-full flex-1 bg-primary transition-all",
      color_class
    ].compact.join(" ")
  end

  def color_class
    case progress_percentage
    when 0..25
      "bg-red-500"
    when 26..50
      "bg-yellow-500"
    when 51..75
      "bg-blue-500"
    when 76..100
      "bg-green-500"
    else
      "bg-primary"
    end
  end
end
