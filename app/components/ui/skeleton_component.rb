# frozen_string_literal: true

class Ui::SkeletonComponent < ViewComponent::Base
  def initialize(**options)
    @options = options
  end

  private

  attr_reader :options

  def skeleton_classes
    [
      "animate-pulse rounded-md bg-muted",
      options[:class]
    ].compact.join(" ")
  end
end
