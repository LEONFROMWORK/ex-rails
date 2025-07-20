# frozen_string_literal: true

module Admin
  class AnalysesController < ApplicationController
    before_action :require_admin!
    before_action :set_analysis, only: [ :show ]

    def index
      @analyses = Analysis.all.order(created_at: :desc)
    end

    def show
    end

    private

    def set_analysis
      @analysis = Analysis.find(params[:id])
    end
  end
end
