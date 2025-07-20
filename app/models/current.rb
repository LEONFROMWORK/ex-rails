# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :request_id
  attribute :user_agent
  attribute :ip_address

  resets { Time.zone = nil }

  def user=(user)
    super
    Time.zone = "Asia/Seoul"
  end
end
