# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:credits) }
    it 'validates uniqueness of email case insensitive' do
      user = build(:user, email: 'test@example.com')
      expect(user).to validate_uniqueness_of(:email).case_insensitive
    end
    it { should validate_numericality_of(:credits).is_greater_than_or_equal_to(0) }
  end

  describe 'associations' do
    it { should have_many(:excel_files).dependent(:destroy) }
    it { should have_many(:analyses).dependent(:destroy) }
    it { should have_many(:chat_conversations).dependent(:destroy) }
    it { should have_many(:payment_intents).dependent(:destroy) }
    it { should have_many(:payments).dependent(:destroy) }
    it { should have_one(:subscription).dependent(:destroy) }
  end

  describe 'enums' do
    it { should define_enum_for(:role).with_values(user: 0, admin: 1, super_admin: 2) }
    it { should define_enum_for(:tier).with_values(free: 0, basic: 1, pro: 2, enterprise: 3) }
  end

  describe 'callbacks' do
    describe 'before_create' do
      it 'generates a referral code' do
        user = build(:user, referral_code: nil)
        user.save!

        expect(user.referral_code).to be_present
        expect(user.referral_code).to match(/\A[A-Z0-9]{8}\z/)
      end

      it 'generates unique referral codes' do
        user1 = create(:user)
        user2 = create(:user)

        expect(user1.referral_code).not_to eq(user2.referral_code)
      end
    end

    describe 'before_save' do
      it 'downcases email' do
        user = create(:user, email: 'TEST@EXAMPLE.COM')
        expect(user.email).to eq('test@example.com')
      end
    end
  end

  describe '#active?' do
    it 'returns true when email is verified' do
      user = create(:user, email_verified: true)
      expect(user).to be_active
    end

    it 'returns false when email is not verified' do
      user = create(:user, email_verified: false)
      expect(user).not_to be_active
    end
  end

  describe '#can_access_admin?' do
    it 'returns true for admin users' do
      admin = create(:user, role: :admin)
      expect(admin.can_access_admin?).to be true
    end

    it 'returns true for super_admin users' do
      super_admin = create(:user, role: :super_admin)
      expect(super_admin.can_access_admin?).to be true
    end

    it 'returns false for regular users' do
      user = create(:user, role: :user)
      expect(user.can_access_admin?).to be false
    end
  end

  describe '#can_use_ai_tier?' do
    context 'for tier 1' do
      it 'returns true when user has sufficient credits' do
        user = create(:user, credits: 10)
        expect(user.can_use_ai_tier?(1)).to be true
      end

      it 'returns false when user has insufficient credits' do
        user = create(:user, credits: 3)
        expect(user.can_use_ai_tier?(1)).to be false
      end
    end

    context 'for tier 2' do
      it 'returns true for pro user with sufficient credits' do
        user = create(:user, tier: :pro, credits: 100)
        expect(user.can_use_ai_tier?(2)).to be true
      end

      it 'returns true for enterprise user with sufficient credits' do
        user = create(:user, tier: :enterprise, credits: 100)
        expect(user.can_use_ai_tier?(2)).to be true
      end

      it 'returns false for free user even with sufficient credits' do
        user = create(:user, tier: :free, credits: 100)
        expect(user.can_use_ai_tier?(2)).to be false
      end

      it 'returns false for pro user with insufficient credits' do
        user = create(:user, tier: :pro, credits: 10)
        expect(user.can_use_ai_tier?(2)).to be false
      end
    end

    it 'returns false for invalid tier' do
      user = create(:user, credits: 100)
      expect(user.can_use_ai_tier?(3)).to be false
    end
  end

  describe '#consume_credits!' do
    it 'reduces credits by specified amount' do
      user = create(:user, credits: 100)
      user.consume_credits!(30)

      expect(user.reload.credits).to eq(70)
    end

    it 'raises error when insufficient credits' do
      user = create(:user, credits: 10)

      expect {
        user.consume_credits!(20)
      }.to raise_error(Common::Errors::InsufficientCreditsError)
    end

    it 'provides error details in exception' do
      user = create(:user, credits: 10)

      begin
        user.consume_credits!(20)
      rescue Common::Errors::InsufficientCreditsError => e
        expect(e.message).to include('Required: 20')
        expect(e.message).to include('Available: 10')
      end
    end
  end

  describe '#add_credits!' do
    it 'increases credits by specified amount' do
      user = create(:user, credits: 50)
      user.add_credits!(25)

      expect(user.reload.credits).to eq(75)
    end
  end

  describe '#has_active_subscription?' do
    it 'returns true when user has active subscription' do
      user = create(:user)
      create(:subscription, user: user, status: :active)

      expect(user.has_active_subscription?).to be true
    end

    it 'returns false when user has no subscription' do
      user = create(:user)
      expect(user.has_active_subscription?).to be false
    end

    it 'returns false when subscription is inactive' do
      user = create(:user)
      create(:subscription, user: user, status: :canceled)

      expect(user.has_active_subscription?).to be false
    end
  end

  describe '#total_spent' do
    it 'returns sum of completed payments' do
      user = create(:user)
      create(:payment, user: user, amount: 1000, status: :completed)
      create(:payment, user: user, amount: 500, status: :completed)
      create(:payment, user: user, amount: 200, status: :refunded) # Should not be included

      expect(user.total_spent).to eq(1500)
    end
  end

  describe '#payment_history' do
    it 'returns recent payments with payment_intent' do
      user = create(:user)
      payment_intent = create(:payment_intent, user: user)
      payment = create(:payment, user: user, payment_intent: payment_intent)

      history = user.payment_history
      expect(history).to include(payment)
    end

    it 'limits to 10 most recent payments' do
      user = create(:user)
      15.times { create(:payment, user: user) }

      history = user.payment_history
      expect(history.count).to eq(10)
    end
  end

  describe '#pending_payments' do
    it 'returns only pending payment intents' do
      user = create(:user)
      pending_intent = create(:payment_intent, user: user, status: :pending)
      completed_intent = create(:payment_intent, user: user, status: :completed)

      pending = user.pending_payments
      expect(pending).to include(pending_intent)
      expect(pending).not_to include(completed_intent)
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only verified users' do
        verified_user = create(:user, email_verified: true)
        unverified_user = create(:user, email_verified: false)

        active_users = User.active
        expect(active_users).to include(verified_user)
        expect(active_users).not_to include(unverified_user)
      end
    end

    describe '.by_tier' do
      it 'returns users of specified tier' do
        pro_user = create(:user, tier: :pro)
        free_user = create(:user, tier: :free)

        pro_users = User.by_tier(:pro)
        expect(pro_users).to include(pro_user)
        expect(pro_users).not_to include(free_user)
      end
    end

    describe '.with_credits' do
      it 'returns users with positive credit balance' do
        user_with_credits = create(:user, credits: 10)
        user_without_credits = create(:user, credits: 0)

        users_with_credits = User.with_credits
        expect(users_with_credits).to include(user_with_credits)
        expect(users_with_credits).not_to include(user_without_credits)
      end
    end
  end

  describe 'email format validation' do
    it 'accepts valid email formats' do
      valid_emails = [
        'user@example.com',
        'user.name@example.com',
        'user+tag@example.com',
        'user123@example-domain.com'
      ]

      valid_emails.each do |email|
        user = build(:user, email: email)
        expect(user).to be_valid, "#{email} should be valid"
      end
    end

    it 'rejects invalid email formats' do
      invalid_emails = [
        'invalid',
        '@example.com',
        'user@'
      ]

      invalid_emails.each do |email|
        user = build(:user, email: email)
        expect(user).not_to be_valid, "#{email} should be invalid"
      end
    end
  end
end
