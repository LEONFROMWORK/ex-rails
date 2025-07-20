module Ui
  class SelectComponent < ViewComponent::Base
    def initialize(name:, options:, label: nil, selected: nil, prompt: nil, required: false, error: nil, **attrs)
      @name = name
      @options = options
      @label = label
      @selected = selected
      @prompt = prompt
      @required = required
      @error = error
      @attrs = attrs
    end

    private

    attr_reader :name, :options, :label, :selected, :prompt, :required, :error, :attrs

    def select_classes
      [
        "flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
        error ? "border-destructive" : nil,
        attrs[:class]
      ].compact.join(" ")
    end

    def label_classes
      [
        "text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70",
        error ? "text-destructive" : nil
      ].compact.join(" ")
    end

    def select_attributes
      {
        id: name,
        name: name,
        class: select_classes
      }.merge(attrs.except(:class))
    end
  end
end
