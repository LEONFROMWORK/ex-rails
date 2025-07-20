# == Schema Information
#
# Table name: payments
#
#  id              :bigint           not null, primary key
#  user_id         :bigint           not null
#  transaction_id  :string
#  order_id        :string
#  payment_method  :string
#  amount          :integer
#  currency        :string
#  status          :string
#  approved_at     :datetime
#  canceled_at     :datetime
#  failed_at       :datetime
#  card_number     :string
#  card_type       :string
#  receipt_url     :string
#  checkout_url    :string
#  failure_code    :string
#  failure_message :string
#  metadata        :jsonb
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

class Payment < ApplicationRecord
  belongs_to :user

  # Status constants
  STATUSES = {
    pending: "PENDING",
    ready: "READY",
    in_progress: "IN_PROGRESS",
    done: "DONE",
    canceled: "CANCELED",
    partial_canceled: "PARTIAL_CANCELED",
    aborted: "ABORTED",
    expired: "EXPIRED"
  }.freeze

  # Payment method constants
  PAYMENT_METHODS = {
    card: "카드",
    virtual_account: "가상계좌",
    easy_pay: "간편결제",
    mobile: "휴대폰",
    transfer: "계좌이체",
    culture_gift_certificate: "문화상품권",
    book_gift_certificate: "도서문화상품권",
    game_gift_certificate: "게임문화상품권"
  }.freeze

  # Validations
  validates :transaction_id, presence: true, uniqueness: true
  validates :order_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES.values }
  validates :payment_method, presence: true

  # Scopes
  scope :pending, -> { where(status: STATUSES[:pending]) }
  scope :completed, -> { where(status: STATUSES[:done]) }
  scope :failed, -> { where(status: [ STATUSES[:canceled], STATUSES[:aborted], STATUSES[:expired] ]) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults

  # Instance methods
  def pending?
    status == STATUSES[:pending]
  end

  def completed?
    status == STATUSES[:done]
  end

  def failed?
    [ STATUSES[:canceled], STATUSES[:aborted], STATUSES[:expired] ].include?(status)
  end

  def can_cancel?
    [ STATUSES[:ready], STATUSES[:in_progress], STATUSES[:done] ].include?(status)
  end

  def mark_as_approved!(approved_at = Time.current)
    update!(
      status: STATUSES[:done],
      approved_at: approved_at
    )
  end

  def mark_as_canceled!(canceled_at = Time.current)
    update!(
      status: STATUSES[:canceled],
      canceled_at: canceled_at
    )
  end

  def mark_as_failed!(failure_code, failure_message, failed_at = Time.current)
    update!(
      status: STATUSES[:aborted],
      failure_code: failure_code,
      failure_message: failure_message,
      failed_at: failed_at
    )
  end

  def formatted_amount
    "#{currency} #{amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
  end

  private

  def set_defaults
    self.currency ||= "KRW"
    self.status ||= STATUSES[:pending]
    self.metadata ||= {}
  end
end
