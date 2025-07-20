# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
    helper_method :current_user, :user_signed_in?
  end

  private

  def authenticate_user!
    redirect_to login_path, alert: "Please log in to continue" unless user_signed_in?
  end

  def user_signed_in?
    current_user.present?
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def set_current_user
    Current.user = current_user
  end

  def login(user)
    session[:user_id] = user.id
    @current_user = user
    set_current_user
  end

  def logout
    session.delete(:user_id)
    @current_user = nil
    Current.user = nil
  end

  def require_admin!
    authenticate_user!
    redirect_to root_path, alert: "Not authorized" unless current_user.can_access_admin?
  end
end
