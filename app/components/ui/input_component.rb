# frozen_string_literal: true

class Ui::InputComponent < ViewComponent::Base
  def initialize(name:, label: nil, placeholder: nil, type: "text", required: false, value: nil, error: nil, **options)
    @name = name
    @label = label
    @placeholder = placeholder
    @type = type
    @required = required
    @value = value
    @error = error
    @options = options
  end

  private

  attr_reader :name, :label, :placeholder, :type, :required, :value, :error, :options

  def input_classes
    base_classes = [
      "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2",
      "text-sm ring-offset-background",
      "file:border-0 file:bg-transparent file:text-sm file:font-medium",
      "placeholder:text-muted-foreground",
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50"
    ]

    if error
      base_classes << "border-destructive"
    end

    base_classes.join(" ")
  end

  def label_classes
    base_classes = [ "text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70" ]
    base_classes << "text-destructive" if error
    base_classes.join(" ")
  end

  def input_attributes
    attrs = {
      id: name,
      name: name,
      type: type,
      class: input_classes,
      value: value,
      placeholder: placeholder
    }

    attrs[:required] = true if required
    attrs.merge!(options)
    attrs
  end
end
