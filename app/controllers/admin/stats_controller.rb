# frozen_string_literal: true

module Admin
  class StatsController < ApplicationController
    before_action :require_admin!

    def index
      @stats = {
        users: {
          total: User.count,
          active: User.where("last_sign_in_at > ?", 1.week.ago).count,
          new_this_week: User.where("created_at > ?", 1.week.ago).count
        },
        files: {
          total: ExcelFile.count,
          processed: ExcelFile.where(status: "analyzed").count,
          failed: ExcelFile.where(status: "failed").count
        },
        analyses: {
          total: Analysis.count,
          this_week: Analysis.where("created_at > ?", 1.week.ago).count,
          tier1: Analysis.where(ai_tier_used: "tier1").count,
          tier2: Analysis.where(ai_tier_used: "tier2").count
        }
      }
    end
  end
end
