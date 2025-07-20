# frozen_string_literal: true

class Ui::CardComponent < ViewComponent::Base
  renders_one :header
  renders_one :footer

  def initialize(padding: true, **options)
    @padding = padding
    @options = options
  end

  def call
    tag.div(class: card_classes, **@options) do
      if header?
        concat tag.div(header, class: header_classes)
      end

      concat tag.div(content, class: body_classes)

      if footer?
        concat tag.div(footer, class: footer_classes)
      end
    end
  end

  private

  def card_classes
    [
      "rounded-lg border bg-card text-card-foreground shadow-sm",
      @options[:class]
    ].compact.join(" ")
  end

  def header_classes
    [
      "flex flex-col space-y-1.5 border-b",
      @padding ? "p-6" : ""
    ].compact.join(" ")
  end

  def body_classes
    @padding ? "p-6 pt-0" : ""
  end

  def footer_classes
    [
      "flex items-center border-t",
      @padding ? "p-6 pt-0" : ""
    ].compact.join(" ")
  end
end
