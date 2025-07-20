# frozen_string_literal: true

# Railway 배포 시 데이터베이스 연결 실패 대응

Rails.application.config.after_initialize do
  # DATABASE_URL이 없거나 연결 실패 시 경고만 출력하고 계속 진행
  begin
    if Rails.env.production? && ENV["DATABASE_URL"].blank?
      Rails.logger.warn "⚠️  DATABASE_URL이 설정되지 않았습니다."
      Rails.logger.warn "🔧 Railway 대시보드에서 PostgreSQL 서비스를 추가하세요."
      Rails.logger.warn "📋 https://railway.app/project/23715624-2291-4a72-9689-cd8eeedb31d1"
    end

    # 데이터베이스 연결 테스트
    ActiveRecord::Base.connection.execute("SELECT 1") if defined?(ActiveRecord::Base)
    Rails.logger.info "✅ 데이터베이스 연결 성공"

  rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
    Rails.logger.warn "⚠️  데이터베이스 연결 실패: #{e.message}"
    Rails.logger.warn "🔧 Railway에서 PostgreSQL 서비스 추가 후 재배포 필요"

    # 연결 실패해도 애플리케이션은 계속 실행
    # 단, 데이터베이스 기능은 제한됨

  rescue StandardError => e
    Rails.logger.error "❌ 예상치 못한 데이터베이스 오류: #{e.message}"
  end
end
