# frozen_string_literal: true

# 서비스 객체의 베이스 클래스
# Command Pattern 구현으로 비즈니스 로직을 캡슐화
class ApplicationService
  def self.call(*args, **kwargs)
    new(*args, **kwargs).call
  end

  def call
    raise NotImplementedError, "Subclass must implement #call method"
  end
end
