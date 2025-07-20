# == Schema Information
#
# Table name: billing_keys
#
#  id               :bigint           not null, primary key
#  user_id          :bigint           not null
#  billing_key      :string
#  customer_key     :string
#  card_number      :string
#  card_type        :string
#  card_owner_type  :string
#  issuer_code      :string
#  acquirer_code    :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#

class BillingKey < ApplicationRecord
  belongs_to :user
  has_many :payment_methods, dependent: :destroy

  # Validations
  validates :billing_key, presence: true, uniqueness: true
  validates :customer_key, presence: true, uniqueness: true
  validates :card_number, presence: true

  # Scopes
  scope :active, -> { where("created_at > ?", 2.years.ago) }

  # Instance methods
  def masked_card_number
    return nil unless card_number.present?
    "#{card_number[0..3]}****#{card_number[-4..]}"
  end

  def card_brand
    case issuer_code
    when "BC", "361", "364", "365"
      "BC카드"
    when "CNB", "388"
      "광주은행"
    when "IBK", "003", "004", "005", "006"
      "기업은행"
    when "KDB", "002"
      "산업은행"
    when "CITI", "027", "028", "029", "030", "031", "032", "033"
      "씨티은행"
    when "DGB", "039"
      "대구은행"
    when "BNK", "045"
      "부산은행"
    when "KJB", "034"
      "광주은행"
    when "SUHYUP", "007"
      "수협은행"
    when "SHINHYUP"
      "신협"
    when "NONGSHIM", "048"
      "농협은행"
    when "WOORI", "020"
      "우리은행"
    when "POST", "071"
      "우체국"
    when "HANA", "081"
      "하나은행"
    when "SHINHAN", "088"
      "신한은행"
    when "HYUNDAI", "367"
      "현대카드"
    when "KOOKMIN", "090"
      "국민은행"
    when "KAKAOBANK", "090"
      "카카오뱅크"
    when "KAKAOPAY", "KAKAOPAY"
      "카카오페이"
    when "TOSSBANK", "092"
      "토스뱅크"
    when "SAMSUNG", "365"
      "삼성카드"
    when "LOTTE", "368"
      "롯데카드"
    else
      card_type || "기타"
    end
  end

  def personal?
    card_owner_type == "개인"
  end

  def corporate?
    card_owner_type == "법인"
  end
end
