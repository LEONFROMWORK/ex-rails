# frozen_string_literal: true

# KnowledgeItem 통계 정보를 제공하는 서비스
class KnowledgeItemStatsService < ApplicationService
  def call
    calculate_stats
  end

  private

  def calculate_stats
    items = KnowledgeItem.all

    {
      total_count: items.count,
      average_quality: calculate_average_quality(items),
      last_created: items.maximum(:created_at),
      source_distribution: calculate_source_distribution(items),
      difficulty_distribution: calculate_difficulty_distribution(items),
      usage_stats: calculate_usage_stats(items)
    }
  end

  def calculate_average_quality(items)
    return 0.0 if items.empty?

    total_quality = items.sum(:quality_score)
    (total_quality / items.count.to_f).round(2)
  end

  def calculate_source_distribution(items)
    distribution = items.group(:source).count
    distribution.transform_values(&:to_i)
  end

  def calculate_difficulty_distribution(items)
    distribution = items.group(:difficulty).count

    {
      easy: distribution[0] || 0,
      medium: distribution[1] || 0,
      hard: distribution[2] || 0,
      expert: distribution[3] || 0
    }
  end

  def calculate_usage_stats(items)
    {
      total_searches: items.sum(:search_count),
      total_uses: items.sum(:use_count),
      total_helpful_votes: items.sum(:helpful_votes),
      average_search_per_item: items.average(:search_count)&.to_f&.round(2) || 0.0,
      average_use_per_item: items.average(:use_count)&.to_f&.round(2) || 0.0
    }
  end
end
