class EnablePgvectorExtension < ActiveRecord::Migration[8.0]
  def change
    # pgvector gem 임시 비활성화로 인해 주석 처리
    # enable_extension "vector"
    Rails.logger.info "pgvector 확장 비활성화 - JSON 임베딩 사용"
  end
end
