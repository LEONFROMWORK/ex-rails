# frozen_string_literal: true

class Excel::FileUploadComponent < ViewComponent::Base
  def initialize(user:, max_file_size: 50.megabytes, allowed_types: %w[.xlsx .xls .xlsb .xlsm .xltx .xlt .xltm .ods .csv])
    @user = user
    @max_file_size = max_file_size
    @allowed_types = allowed_types
  end

  private

  attr_reader :user, :max_file_size, :allowed_types

  def can_upload?
    user.credits >= 10
  end

  def max_file_size_mb
    (max_file_size / 1.megabyte).to_i
  end

  def allowed_types_display
    allowed_types.join(", ")
  end

  def upload_zone_classes
    base_classes = [
      "border-2 border-dashed rounded-lg p-6 text-center transition-colors",
      "hover:border-primary/50 hover:bg-primary/5"
    ]

    if can_upload?
      base_classes << "border-border cursor-pointer"
    else
      base_classes << "border-muted cursor-not-allowed opacity-50"
    end

    base_classes.join(" ")
  end

  def upload_input_attributes
    {
      type: "file",
      name: "file",
      id: "file-upload",
      accept: allowed_types.join(","),
      class: "sr-only",
      multiple: false,
      disabled: !can_upload?
    }
  end
end
