class EnablePgvectorExtension < ActiveRecord::Migration[8.0]
  def change
    # pgvector 확장이 설치되지 않은 경우를 대비해 주석 처리
    # enable_extension "vector"

    # 대신 JSON 배열로 임베딩을 저장하도록 함
    # 실제 배포 시 pgvector가 필요하면 주석을 해제
  end
end
