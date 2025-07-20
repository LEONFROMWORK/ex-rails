# == Schema Information
#
# Table name: payment_methods
#
#  id           :bigint           not null, primary key
#  user_id      :bigint           not null
#  method_type  :string
#  is_default   :boolean          default(FALSE)
#  card_number  :string
#  card_type    :string
#  billing_key_id :bigint
#  metadata     :jsonb
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#

class PaymentMethod < ApplicationRecord
  belongs_to :user
  belongs_to :billing_key, optional: true

  # Validations
  validates :method_type, presence: true
  validates :is_default, uniqueness: { scope: :user_id }, if: :is_default?

  # Scopes
  scope :default, -> { where(is_default: true) }
  scope :active, -> { joins(:billing_key).merge(BillingKey.active) }

  # Callbacks
  before_save :ensure_single_default

  # Instance methods
  def display_name
    case method_type
    when "card"
      "#{card_brand} #{masked_card_number}"
    when "billing_key"
      billing_key&.masked_card_number || "등록된 카드"
    else
      method_type
    end
  end

  def masked_card_number
    return billing_key.masked_card_number if billing_key.present?
    return nil unless card_number.present?
    "****#{card_number[-4..]}"
  end

  def card_brand
    return billing_key.card_brand if billing_key.present?
    card_type || "카드"
  end

  def make_default!
    transaction do
      user.payment_methods.update_all(is_default: false)
      update!(is_default: true)
    end
  end

  private

  def ensure_single_default
    if is_default? && is_default_changed?
      user.payment_methods.where.not(id: id).update_all(is_default: false)
    end
  end
end
