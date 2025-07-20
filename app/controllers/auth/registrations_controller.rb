# frozen_string_literal: true

module Auth
  class RegistrationsController < ApplicationController
    skip_before_action :authenticate_user!, only: [ :new, :create ]

    def new
      # Redirect to login page since we're using OAuth only
      redirect_to auth_login_path
    end

    def create
      @user = User.new(user_params)
      @user.referred_by = params[:referral_code] if params[:referral_code].present?

      if @user.save
        # Award referral bonus if applicable
        award_referral_bonus(@user) if @user.referred_by.present?

        login(@user)
        redirect_to root_path, notice: "Welcome to ExcelApp! You have #{@user.credits} free credits to start."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def user_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation)
    end

    def award_referral_bonus(new_user)
      referrer = User.find_by(referral_code: new_user.referred_by)
      return unless referrer

      # Award credits to both users
      referrer.add_credits!(500)
      new_user.add_credits!(200)

      # You might want to create a referral record here for tracking
    end
  end
end
