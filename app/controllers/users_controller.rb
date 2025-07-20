# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!

  def profile
    @user = current_user
  end

  def settings
    @user = current_user
  end

  private

  def authenticate_user!
    redirect_to login_path unless user_signed_in?
  end
end
