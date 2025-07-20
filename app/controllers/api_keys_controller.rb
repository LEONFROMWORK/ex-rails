# frozen_string_literal: true

class ApiKeysController < ApplicationController
  before_action :authenticate_user!

  def index
    @api_keys = current_user.api_keys.order(created_at: :desc) if current_user.respond_to?(:api_keys)
    @api_keys ||= []
  end

  def new
    @api_key = ApiKey.new if defined?(ApiKey)
    redirect_to api_keys_path, alert: "API Keys feature not yet implemented" unless defined?(ApiKey)
  end

  def create
    redirect_to api_keys_path, alert: "API Keys feature not yet implemented"
  end

  def edit
    redirect_to api_keys_path, alert: "API Keys feature not yet implemented"
  end

  def update
    redirect_to api_keys_path, alert: "API Keys feature not yet implemented"
  end

  def destroy
    redirect_to api_keys_path, alert: "API Keys feature not yet implemented"
  end

  private

  def authenticate_user!
    redirect_to login_path unless user_signed_in?
  end
end
