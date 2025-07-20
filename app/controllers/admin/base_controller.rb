# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :require_admin!

    private

    def require_admin!
      authenticate_user!

      # Only allow specific admin email
      unless current_user&.admin? || current_user&.super_admin?
        redirect_to root_path, alert: "접근 권한이 없습니다."
      end
    end
  end
end
