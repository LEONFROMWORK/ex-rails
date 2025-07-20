# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password validations: false

  # Associations
  has_many :excel_files, dependent: :destroy
  has_many :analyses, dependent: :destroy
  has_many :chat_conversations, dependent: :destroy
  has_many :payment_intents, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :billing_keys, dependent: :destroy
  has_many :payment_methods, dependent: :destroy
  has_one :subscription, dependent: :destroy

  # Enums
  enum :role, { user: 0, admin: 1, super_admin: 2 }
  enum :tier, { free: 0, basic: 1, pro: 2, enterprise: 3 }

  # Validations
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :credits, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :password, presence: true, length: { minimum: 6 }, if: :password_required?

  # Callbacks
  before_create :generate_referral_code
  before_save :downcase_email
  after_update :invalidate_user_cache
  after_destroy :invalidate_user_cache

  # Scopes
  scope :active, -> { where(email_verified: true) }
  scope :by_tier, ->(tier) { where(tier: tier) }
  scope :with_credits, -> { where("credits > 0") }

  # Instance methods
  def active?
    email_verified?
  end

  def can_access_admin?
    admin? || super_admin?
  end

  def can_use_ai_tier?(tier)
    return true unless Rails.application.config.features[:subscription_required]

    case tier
    when 1 then credits >= 5
    when 2 then credits >= 50 && (pro? || enterprise?)
    else false
    end
  end

  def has_active_subscription?
    subscription.present? && subscription.active?
  end

  def consume_credits!(amount)
    return true unless Rails.application.config.features[:subscription_required]

    raise ::Common::Errors::InsufficientCreditsError.new(required: amount, available: credits) if credits < amount

    decrement!(:credits, amount)
  end

  def add_credits!(amount)
    increment!(:credits, amount)
  end

  def total_spent
    payments.completed.sum(:amount)
  end

  def payment_history
    payments.includes(:payment_intent).recent.limit(10)
  end

  def pending_payments
    payment_intents.pending
  end

  # OAuth methods
  def self.from_omniauth(auth)
    user = where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.name = auth.info.name
      user.avatar_url = auth.info.image
      user.password = SecureRandom.hex(16) # Random password for OAuth users
      user.email_verified = true # OAuth providers verify email
    end

    # Set admin role for specific email
    user.set_admin_if_authorized
    user
  end

  def oauth_user?
    provider.present? && uid.present?
  end

  # Class methods
  def self.system_user
    @system_user ||= find_or_create_by!(email: "system@excelapp.local") do |user|
      user.name = "System"
      user.password = SecureRandom.hex(32)
      user.role = :admin
      user.tier = :enterprise
      user.credits = 999999
    end
  end

  private

  def generate_referral_code
    self.referral_code = loop do
      code = SecureRandom.alphanumeric(8).upcase
      break code unless User.exists?(referral_code: code)
    end
  end

  def downcase_email
    self.email = email&.downcase
  end

  def invalidate_user_cache
    CacheService.instance.invalidate_user_cache(id) if persisted?
  end

  def password_required?
    !oauth_user? && password_digest.blank?
  end

  public

  def set_admin_if_authorized
    # Add your admin email here
    admin_emails = ENV.fetch("ADMIN_EMAILS", "").split(",").map(&:strip)

    if admin_emails.include?(email)
      update_column(:role, :super_admin) unless super_admin?
    end
  end
end
