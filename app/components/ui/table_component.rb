# frozen_string_literal: true

class Ui::TableComponent < ViewComponent::Base
  def initialize(**options)
    @options = options
  end

  private

  attr_reader :options

  def table_classes
    [
      "w-full caption-bottom text-sm",
      options[:class]
    ].compact.join(" ")
  end
end
