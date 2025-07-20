# frozen_string_literal: true

class Ui::ErrorBoundaryComponent < ViewComponent::Base
  attr_reader :error, :fallback_content, :show_details, :retry_action, :class_names

  def initialize(
    error: nil,
    fallback_content: nil,
    show_details: Rails.env.development?,
    retry_action: nil,
    class: nil
  )
    @error = error
    @fallback_content = fallback_content
    @show_details = show_details
    @retry_action = retry_action
    @class_names = binding.local_variable_get(:class)
  end

  def render?
    error.present?
  end

  private

  def container_classes
    base = "rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4"
    [ base, class_names ].compact.join(" ")
  end

  def error_title
    case error
    when ActiveRecord::RecordNotFound
      "리소스를 찾을 수 없습니다"
    when ActionController::RoutingError
      "페이지를 찾을 수 없습니다"
    when ActiveRecord::ConnectionNotEstablished
      "데이터베이스 연결 오류"
    when StandardError
      "오류가 발생했습니다"
    else
      "알 수 없는 오류"
    end
  end

  def error_message
    return fallback_content if fallback_content.present?

    case error
    when ActiveRecord::RecordNotFound
      "요청하신 리소스를 찾을 수 없습니다. URL을 확인해주세요."
    when ActionController::RoutingError
      "요청하신 페이지가 존재하지 않습니다."
    when ActiveRecord::ConnectionNotEstablished
      "데이터베이스에 연결할 수 없습니다. 잠시 후 다시 시도해주세요."
    when StandardError
      "처리 중 오류가 발생했습니다. 문제가 지속되면 고객지원팀에 문의해주세요."
    else
      "알 수 없는 오류가 발생했습니다."
    end
  end

  def error_id
    @error_id ||= SecureRandom.hex(8)
  end

  def should_show_retry?
    retry_action.present? && !error.is_a?(ActiveRecord::RecordNotFound)
  end
end
