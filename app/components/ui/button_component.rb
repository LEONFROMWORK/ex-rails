# frozen_string_literal: true

class Ui::ButtonComponent < ViewComponent::Base
  VARIANTS = {
    default: "bg-primary text-primary-foreground hover:bg-primary/90",
    destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
    outline: "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
    secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
    ghost: "hover:bg-accent hover:text-accent-foreground",
    link: "text-primary underline-offset-4 hover:underline"
  }.freeze

  SIZES = {
    default: "h-10 px-4 py-2",
    sm: "h-9 rounded-md px-3",
    lg: "h-11 rounded-md px-8",
    icon: "h-10 w-10"
  }.freeze

  def initialize(variant: :default, size: :default, type: "button", **options)
    @variant = variant
    @size = size
    @type = type
    @options = options
  end

  def call
    tag.button(
      content,
      type: @type,
      class: button_classes,
      **@options
    )
  end

  private

  def button_classes
    [
      base_classes,
      variant_classes,
      size_classes,
      @options[:class]
    ].compact.join(" ")
  end

  def base_classes
    "inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none"
  end

  def variant_classes
    VARIANTS[@variant] || VARIANTS[:default]
  end

  def size_classes
    SIZES[@size] || SIZES[:default]
  end
end
