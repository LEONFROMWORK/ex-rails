# pgvector 활성화 가이드 (선택사항)

## 현재 상태
- ❌ pgvector 비활성화 (JSON 임베딩 사용)
- ✅ 배포 가능한 상태

## pgvector 활성화 방법

### 1. Railway PostgreSQL에서 pgvector 지원 확인
```sql
-- Railway 데이터베이스 콘솔에서 실행
CREATE EXTENSION IF NOT EXISTS vector;
```

### 2. 마이그레이션 파일 수정
```ruby
# db/migrate/20250719173440_enable_pgvector_extension.rb
def change
  enable_extension "vector"  # 주석 해제
end
```

### 3. 임베딩 컬럼 추가
```bash
rails generate migration AddEmbeddingToRagDocuments embedding:vector
```

### 4. 모델 업데이트
```ruby
# app/models/rag_document.rb
has_neighbors :embedding
```

## 외부 벡터 DB 사용

### Pinecone
1. https://pinecone.io 가입
2. API 키 생성
3. `PINECONE_API_KEY` 환경변수 설정

### Weaviate Cloud
1. https://console.weaviate.cloud 가입  
2. 클러스터 생성
3. `WEAVIATE_URL`, `WEAVIATE_API_KEY` 설정

## 권장사항
- 🎯 **현재 배포**: JSON 임베딩 사용 (별도 설정 불필요)
- 🚀 **향후 최적화**: pgvector 활성화
- 📈 **스케일링**: 외부 벡터 DB 고려