class ApplicationController < ActionController::Base
  include Authentication
  include FormulaEngineHelper
  include ErrorHandling

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # CSRF protection
  protect_from_forgery with: :exception

  # Authentication
  before_action :authenticate_user!

  # Set current attributes for logging and tracking
  before_action :set_current_attributes

  # Set theme from cookie
  before_action :set_theme

  # Set locale
  before_action :set_locale

  # Cache service helper
  def cache_service
    @cache_service ||= CacheService.instance
  end
  helper_method :cache_service

  private

  def set_current_attributes
    Current.request_id = request.uuid
    Current.user_agent = request.user_agent
    Current.ip_address = request.remote_ip
    Current.user = current_user if respond_to?(:current_user)
  end

  def set_theme
    @theme = cookies[:theme] || "light"
  end

  def set_locale
    I18n.locale = params[:locale] || cookies[:locale] || I18n.default_locale
    cookies[:locale] = I18n.locale
  end

  def default_url_options
    { locale: I18n.locale }
  end
end
