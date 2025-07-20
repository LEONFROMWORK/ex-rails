class VueController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index, :test, :status ]

  def index
    # Demo page for Vue.js integration
  end

  def test
    # Test page for Vue.js
  end

  def status
    respond_to do |format|
      format.json
    end
  end
end
