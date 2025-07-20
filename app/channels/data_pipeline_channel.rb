# frozen_string_literal: true

class DataPipelineChannel < ApplicationCable::Channel
  def subscribed
    # Verify user is admin
    return reject unless current_user&.admin?

    stream_from "data_pipeline_logs"

    Rails.logger.info("Admin user #{current_user.id} subscribed to data pipeline logs")
  end

  def unsubscribed
    Rails.logger.info("Admin user #{current_user&.id} unsubscribed from data pipeline logs")
  end

  # Class method to broadcast log messages
  def self.broadcast_log(source, type, message, item = nil)
    ActionCable.server.broadcast(
      "data_pipeline_logs",
      {
        source: source,
        type: type,
        message: message,
        item: item,
        timestamp: Time.current.iso8601
      }
    )
  end

  # Convenience methods for different log types
  def self.broadcast_collection_start(source)
    broadcast_log(source, "collection_start", "#{source} 데이터 수집 시작")
  end

  def self.broadcast_collection_stop(source)
    broadcast_log(source, "collection_stop", "#{source} 데이터 수집 중지")
  end

  def self.broadcast_item_collected(source, item)
    broadcast_log(
      source,
      "item_collected",
      "새 게시물 수집됨",
      format_item_for_broadcast(item)
    )
  end

  def self.broadcast_batch_complete(source, count)
    broadcast_log(source, "batch_complete", "#{count}개 항목의 배치 처리 완료")
  end

  def self.broadcast_error(source, error_message)
    broadcast_log(source, "error", error_message)
  end

  private

  def self.format_item_for_broadcast(item)
    return nil unless item

    # Format item data for client display
    {
      title: extract_title(item),
      content: extract_content_preview(item),
      has_images: has_images?(item)
    }
  end

  def self.extract_title(item)
    if item.is_a?(Hash)
      item["title"] || item[:title] || "Untitled"
    else
      item.try(:title) || "Untitled"
    end
  end

  def self.extract_content_preview(item)
    content = if item.is_a?(Hash)
      item["content"] || item[:content] || item["body"] || item[:body] ||
      item["answer"] || item[:answer] || ""
    else
      item.try(:content) || item.try(:body) || item.try(:answer) || ""
    end

    # Clean up content and limit length
    content.strip.gsub(/\s+/, " ").truncate(150)
  end

  def self.has_images?(item)
    if item.is_a?(Hash)
      content = item["content"] || item[:content] || item["body"] || item[:body] || ""
    else
      content = item.try(:content) || item.try(:body) || ""
    end

    # Check for image indicators
    content.downcase.include?("image") ||
    content.downcase.include?("img") ||
    content.downcase.include?("screenshot") ||
    content.downcase.include?("photo") ||
    content.downcase.include?("pic") ||
    content.include?("![") || # Markdown image
    content.include?("<img") || # HTML image
    content.include?("이미지") || # Korean
    content.include?("그림") || # Korean
    content.include?("스크린샷") # Korean
  end
end
