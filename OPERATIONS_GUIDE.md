# ExcelApp Rails - 운영 가이드

## 목차
1. [일상 운영 절차](#일상-운영-절차)
2. [모니터링 및 알림](#모니터링-및-알림)
3. [백업 및 복구](#백업-및-복구)
4. [성능 튜닝](#성능-튜닝)
5. [장애 대응](#장애-대응)
6. [보안 관리](#보안-관리)
7. [용량 관리](#용량-관리)
8. [정기 유지보수](#정기-유지보수)

## 일상 운영 절차

### 1. 매일 점검 사항
#### 시스템 상태 확인
```bash
# 애플리케이션 상태 확인
curl -s http://localhost/up | jq '.'

# FormulaEngine 서비스 상태 확인
curl -s http://localhost:3002/health | jq '.'

# 데이터베이스 연결 확인
rails runner "puts ActiveRecord::Base.connection.active? ? 'OK' : 'FAIL'"

# Redis 연결 확인
redis-cli ping
```

#### 로그 확인
```bash
# 에러 로그 확인 (최근 24시간)
grep -i error log/production.log | tail -20

# 성능 이슈 확인
grep "Completed.*[5-9][0-9][0-9]ms" log/production.log | tail -10

# FormulaEngine 에러 확인
grep -i error log/formula_engine.log | tail -10
```

#### 리소스 사용량 점검
```bash
# 메모리 사용량
free -h

# 디스크 사용량
df -h

# CPU 사용률
top -bn1 | grep "Cpu(s)"

# 프로세스 확인
ps aux | grep -E "(rails|node)" | grep -v grep
```

### 2. 주간 점검 사항
- [ ] 백업 상태 확인
- [ ] 보안 업데이트 확인
- [ ] 성능 메트릭 리뷰
- [ ] 에러율 분석
- [ ] 사용자 피드백 검토
- [ ] 디스크 공간 정리

### 3. 월간 점검 사항
- [ ] 보안 감사
- [ ] 성능 벤치마크
- [ ] 용량 계획 검토
- [ ] 의존성 업데이트
- [ ] 재해 복구 테스트

## 모니터링 및 알림

### 1. 핵심 메트릭
#### 애플리케이션 메트릭
- **응답 시간**: 평균 < 200ms, 95%ile < 500ms
- **에러율**: < 1%
- **처리량**: requests/second
- **활성 사용자**: 동시 접속자 수

#### 시스템 메트릭
- **CPU 사용률**: < 70%
- **메모리 사용률**: < 80%
- **디스크 사용률**: < 85%
- **네트워크 I/O**: 대역폭 사용량

#### 비즈니스 메트릭
- **파일 업로드 성공률**: > 95%
- **AI 분석 완료율**: > 90%
- **결제 성공률**: > 98%
- **FormulaEngine 응답률**: > 99%

### 2. 알림 설정
#### 긴급 알림 (즉시 대응 필요)
```yaml
# Scout APM 알림 설정
alerts:
  error_rate:
    threshold: 5%
    period: 5m
  response_time:
    threshold: 1000ms
    period: 5m
  memory_usage:
    threshold: 90%
    period: 5m
```

#### 경고 알림 (24시간 내 대응)
- API 응답 시간 증가
- 백그라운드 작업 지연
- 디스크 공간 부족 (80% 초과)
- 데이터베이스 성능 저하

### 3. 대시보드 설정
#### Scout APM 대시보드
- 애플리케이션 성능 개요
- 느린 엔드포인트 분석
- 데이터베이스 쿼리 성능
- 메모리 사용 패턴

#### Sentry 대시보드
- 에러 발생 현황
- 에러 트렌드 분석
- 사용자 영향 분석
- 배포별 에러 비교

## 백업 및 복구

### 1. 데이터베이스 백업
#### 자동 백업 스크립트
```bash
#!/bin/bash
# /opt/scripts/backup_database.sh

set -e

BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="excelapp_rails_production"
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_$DATE.sql.gz"

# 백업 디렉토리 생성
mkdir -p $BACKUP_DIR

# 데이터베이스 백업
pg_dump $DATABASE_URL | gzip > $BACKUP_FILE

# S3에 업로드
aws s3 cp $BACKUP_FILE s3://excelapp-backups/database/

# 로컬 백업 파일 정리 (7일 보관)
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

# 백업 상태 로깅
echo "$(date): Database backup completed - $BACKUP_FILE" >> /var/log/backup.log
```

#### 백업 스케줄 설정
```bash
# crontab -e
# 매일 새벽 2시 백업
0 2 * * * /opt/scripts/backup_database.sh

# 매주 일요일 전체 백업
0 1 * * 0 /opt/scripts/full_backup.sh
```

### 2. 파일 백업
```bash
#!/bin/bash
# 업로드된 파일 백업
rsync -av /var/lib/excelapp/storage/ s3://excelapp-backups/files/

# 로그 파일 백업
tar -czf /tmp/logs_$(date +%Y%m%d).tar.gz log/
aws s3 cp /tmp/logs_$(date +%Y%m%d).tar.gz s3://excelapp-backups/logs/
```

### 3. 복구 절차
#### 데이터베이스 복구
```bash
# 백업에서 복구
gunzip -c backup_file.sql.gz | psql $DATABASE_URL

# 특정 시점으로 복구 (Point-in-Time Recovery)
# PostgreSQL WAL 기반 복구 사용
```

#### 애플리케이션 복구
```bash
# 이전 버전으로 롤백
git checkout v1.2.3
bundle install
rails assets:precompile
systemctl restart excelapp-rails
```

## 성능 튜닝

### 1. 데이터베이스 최적화
#### 인덱스 확인 및 최적화
```sql
-- 누락된 인덱스 확인
SELECT schemaname, tablename, attname, n_distinct, correlation
FROM pg_stats
WHERE schemaname = 'public'
AND n_distinct > 100;

-- 사용되지 않는 인덱스 확인
SELECT s.schemaname, s.tablename, s.indexname, s.idx_scan
FROM pg_stat_user_indexes s
WHERE s.idx_scan = 0;

-- 인덱스 크기 확인
SELECT schemaname, tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;
```

#### 쿼리 성능 분석
```sql
-- 느린 쿼리 확인
SELECT query, mean_time, calls, total_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- 자주 실행되는 쿼리
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

### 2. 애플리케이션 최적화
#### Rails 캐싱 설정
```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store

# 뷰 캐싱 활성화
config.action_controller.perform_caching = true

# HTTP 캐싱 헤더 설정
config.public_file_server.headers = {
  'Cache-Control' => 'public, max-age=31536000'
}
```

#### 백그라운드 작업 최적화
```ruby
# config/application.rb
config.active_job.queue_adapter = :solid_queue

# 큐 우선순위 설정
config.active_job.queue_name_prefix = "excelapp_#{Rails.env}"
```

### 3. 서버 성능 튜닝
#### Ruby/Rails 설정
```bash
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 4 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 16 }
threads threads_count, threads_count

preload_app!

# 메모리 사용량 최적화
ENV['RUBY_GC_HEAP_INIT_SLOTS'] = '1000000'
ENV['RUBY_GC_HEAP_FREE_SLOTS'] = '2000000'
ENV['RUBY_GC_HEAP_GROWTH_FACTOR'] = '1.03'
```

#### PostgreSQL 튜닝
```sql
-- postgresql.conf 최적화 설정
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.7
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
```

## 장애 대응

### 1. 장애 분류
#### P0 (Critical) - 15분 내 대응
- 전체 서비스 중단
- 데이터 손실 위험
- 보안 침해

#### P1 (High) - 1시간 내 대응
- 주요 기능 장애
- 성능 심각한 저하
- API 응답 불가

#### P2 (Medium) - 4시간 내 대응
- 일부 기능 장애
- 성능 저하
- 비핵심 API 문제

#### P3 (Low) - 24시간 내 대응
- 마이너 버그
- UI/UX 문제
- 로깅 이슈

### 2. 일반적인 장애 대응
#### 메모리 부족
```bash
# 메모리 사용량 확인
ps aux --sort=-%mem | head -10

# 캐시 정리
echo 3 > /proc/sys/vm/drop_caches

# 애플리케이션 재시작
systemctl restart excelapp-rails
```

#### 데이터베이스 성능 문제
```sql
-- 활성 연결 확인
SELECT pid, usename, application_name, state, query_start, query
FROM pg_stat_activity
WHERE state != 'idle';

-- 잠금 대기 확인
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement,
       blocking_activity.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

#### FormulaEngine 서비스 장애
```bash
# 서비스 상태 확인
docker ps | grep formula-engine

# 로그 확인
docker logs formula-engine

# 서비스 재시작
docker restart formula-engine

# 헬스체크
curl http://localhost:3002/health
```

### 3. 장애 대응 플레이북
#### 단계별 대응 절차
1. **상황 인지** (1분)
   - 알림 확인
   - 영향 범위 파악

2. **초기 대응** (5분)
   - 임시 조치 실행
   - 관련팀 알림

3. **원인 분석** (15분)
   - 로그 분석
   - 메트릭 확인
   - 가설 수립

4. **해결 실행** (30분)
   - 수정 사항 적용
   - 테스트 실행
   - 모니터링 강화

5. **사후 처리** (24시간)
   - 근본 원인 분석
   - 예방 조치 수립
   - 문서화

## 보안 관리

### 1. 정기 보안 점검
#### 시스템 업데이트
```bash
# 시스템 패키지 업데이트
sudo apt update && sudo apt upgrade

# Ruby 젬 보안 업데이트
bundle audit

# Node.js 패키지 보안 점검
npm audit
```

#### 보안 스캔
```bash
# 코드 보안 스캔
bundle exec brakeman

# 의존성 취약점 스캔
bundle exec bundler-audit

# 컨테이너 보안 스캔 (Docker 사용 시)
docker scan excelapp-rails:latest
```

### 2. 접근 권한 관리
#### 사용자 권한 검토
```bash
# SSH 접근 권한 확인
sudo grep -E "AllowUsers|AllowGroups" /etc/ssh/sshd_config

# sudo 권한 확인
sudo grep -E "^[^#]" /etc/sudoers

# 데이터베이스 사용자 권한 확인
psql -c "\du"
```

### 3. 로그 모니터링
```bash
# 실패한 로그인 시도 확인
sudo grep "Failed password" /var/log/auth.log | tail -20

# suspicious 활동 모니터링
sudo grep -i "suspicious\|attack\|intrusion" /var/log/syslog
```

## 용량 관리

### 1. 디스크 사용량 모니터링
```bash
# 전체 디스크 사용량
df -h

# 디렉토리별 사용량
du -sh /var/lib/excelapp/*
du -sh /var/log/*

# 대용량 파일 찾기
find /var -type f -size +100M -exec ls -lh {} \;
```

### 2. 데이터베이스 용량 관리
```sql
-- 테이블 크기 확인
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 오래된 데이터 정리
DELETE FROM ai_usage_records WHERE created_at < NOW() - INTERVAL '1 year';
DELETE FROM chat_messages WHERE created_at < NOW() - INTERVAL '6 months';
```

### 3. 로그 로테이션
```bash
# /etc/logrotate.d/excelapp-rails
/home/deploy/excelapp-rails/log/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 deploy deploy
    postrotate
        systemctl reload excelapp-rails
    endscript
}
```

## 정기 유지보수

### 1. 월간 작업
- [ ] 보안 패치 적용
- [ ] 성능 메트릭 분석
- [ ] 용량 계획 검토
- [ ] 백업 복구 테스트
- [ ] 의존성 업데이트 검토

### 2. 분기별 작업
- [ ] 전체 시스템 성능 리뷰
- [ ] 보안 감사 실행
- [ ] 재해 복구 계획 테스트
- [ ] 용량 증설 계획 수립
- [ ] 아키텍처 개선 검토

### 3. 연간 작업
- [ ] 인프라 전체 리뷰
- [ ] 보안 정책 업데이트
- [ ] 비용 최적화 검토
- [ ] 기술 스택 업그레이드 계획
- [ ] 팀 교육 및 훈련

## 연락처 및 에스컬레이션

### 1. 운영팀 연락처
- **1차 대응**: operations@excelapp.com
- **기술 리드**: tech-lead@excelapp.com
- **시스템 관리자**: sysadmin@excelapp.com

### 2. 긴급 연락처
- **24/7 온콜**: +82-10-xxxx-xxxx
- **Slack**: #ops-emergency
- **PagerDuty**: https://excelapp.pagerduty.com

### 3. 외부 업체
- **클라우드 공급자**: AWS Support
- **모니터링**: Scout APM Support
- **에러 추적**: Sentry Support

---

## 문서 업데이트

이 문서는 분기별로 검토하고 업데이트해야 합니다.

**마지막 업데이트**: 2025-07-19  
**다음 검토 예정일**: 2025-10-19  
**문서 담당자**: 운영팀