# frozen_string_literal: true

class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index, :theme_test ]

  def index
    @recent_analyses = current_user.analyses.recent.limit(5) if user_signed_in?
    @user_files = current_user.excel_files.recent.limit(3) if user_signed_in?
  end

  def theme_test
    # Theme toggle test page
  end
end
