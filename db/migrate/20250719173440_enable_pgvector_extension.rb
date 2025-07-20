class EnablePgvectorExtension < ActiveRecord::Migration[8.0]
  def change
    # Railway PostgreSQL에서 pgvector 확장 활성화
    enable_extension "vector"
  rescue ActiveRecord::StatementInvalid => e
    # pgvector가 설치되지 않은 경우 JSON 방식으로 폴백
    Rails.logger.warn "pgvector 확장 활성화 실패, JSON 임베딩 사용: #{e.message}"
  end
end
