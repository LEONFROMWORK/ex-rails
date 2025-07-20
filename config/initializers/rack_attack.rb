# frozen_string_literal: true

# Rack::Attack 설정 - 레이트 리미팅 및 보안 강화
class Rack::Attack
  # Redis를 캐시 스토어로 사용 (production에서는 Redis 권장)
  if Rails.env.production?
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
    )
  else
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  # === 로그인 보호 ===

  # 로그인 시도 제한 (IP별)
  throttle("login attempts per IP", limit: 5, period: 15.minutes) do |req|
    req.ip if req.path == "/auth/sessions" && req.post?
  end

  # 로그인 시도 제한 (이메일별)
  throttle("login attempts per email", limit: 3, period: 15.minutes) do |req|
    if req.path == "/auth/sessions" && req.post?
      # POST 파라미터에서 이메일 추출
      req.params.dig("user", "email")&.downcase
    end
  end

  # === API 보호 ===

  # API 요청 제한 (인증된 사용자)
  throttle("authenticated API requests", limit: 100, period: 1.hour) do |req|
    if req.path.start_with?("/api/") && (user_id = extract_user_id(req))
      "api_user_#{user_id}"
    end
  end

  # API 요청 제한 (IP별 - 미인증)
  throttle("unauthenticated API requests", limit: 20, period: 1.hour) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # === 파일 업로드 보호 ===

  # 파일 업로드 제한
  throttle("file uploads", limit: 10, period: 1.hour) do |req|
    if req.path == "/excel_files" && req.post?
      if (user_id = extract_user_id(req))
        "upload_user_#{user_id}"
      else
        req.ip
      end
    end
  end

  # === 웹훅 보호 ===

  # 결제 웹훅 제한
  throttle("payment webhooks", limit: 50, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/webhooks/")
  end

  # === 일반 웹 요청 보호 ===

  # 일반 요청 제한 (매우 관대한 제한)
  throttle("general requests", limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/assets")
  end

  # === 악성 요청 차단 ===

  # SQL Injection 패턴 차단
  MALICIOUS_SQL_PATTERNS = [
    /union.*select/i,
    /drop\s+table/i,
    /insert\s+into/i,
    /delete\s+from/i,
    /update.*set/i,
    /exec.*xp_/i
  ].freeze

  blocklist("block SQL injection attempts") do |req|
    query_string = req.query_string.to_s
    MALICIOUS_SQL_PATTERNS.any? { |pattern| query_string.match?(pattern) }
  end

  # 의심스러운 User-Agent 차단
  MALICIOUS_USER_AGENTS = [
    /sqlmap/i,
    /nikto/i,
    /nessus/i,
    /acunetix/i,
    /w3af/i
  ].freeze

  blocklist("block malicious user agents") do |req|
    user_agent = req.user_agent.to_s
    MALICIOUS_USER_AGENTS.any? { |pattern| user_agent.match?(pattern) }
  end

  # === 응답 커스터마이징 ===

  # 스로틀링 응답
  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"]
    retry_after = match_data ? match_data[:period] : 60

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s,
        "X-RateLimit-Limit" => match_data ? match_data[:limit].to_s : "100",
        "X-RateLimit-Remaining" => "0",
        "X-RateLimit-Reset" => (Time.now + retry_after).to_i.to_s
      },
      [ {
        error: "Rate limit exceeded",
        message: "Too many requests. Please try again later.",
        retry_after: retry_after
      }.to_json ]
    ]
  end

  # 차단된 요청 응답
  self.blocklisted_responder = lambda do |req|
    [
      403,
      { "Content-Type" => "application/json" },
      [ {
        error: "Forbidden",
        message: "Your request has been blocked for security reasons."
      }.to_json ]
    ]
  end

  # === 헬퍼 메서드 ===

  private

  def self.extract_user_id(req)
    # JWT 토큰에서 사용자 ID 추출
    auth_header = req.get_header("HTTP_AUTHORIZATION")
    return nil unless auth_header&.start_with?("Bearer ")

    token = auth_header.split(" ").last
    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: "HS256" })
      decoded.first["user_id"]
    rescue JWT::DecodeError, JWT::ExpiredSignature
      nil
    end
  end
end

# === 통지 및 로깅 ===

# 스로틀링 이벤트 로깅
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |name, start, finish, request_id, payload|
  req = payload[:request]

  Rails.logger.warn(
    "Rate limited: #{req.ip} for #{req.path} " \
    "(#{payload[:match_discriminator]}: #{payload[:match_data][:count]}/#{payload[:match_data][:limit]})"
  )

  # 프로덕션에서는 외부 모니터링 서비스에 알림
  if Rails.env.production?
    # Sentry, New Relic 등에 알림 전송
    # Sentry.capture_message("Rate limit exceeded", extra: payload)
  end
end

# 차단 이벤트 로깅
ActiveSupport::Notifications.subscribe("blocklist.rack_attack") do |name, start, finish, request_id, payload|
  req = payload[:request]

  Rails.logger.error(
    "Blocked malicious request: #{req.ip} for #{req.path} " \
    "(User-Agent: #{req.user_agent})"
  )

  # 프로덕션에서는 즉시 알림
  if Rails.env.production?
    # 보안 팀에 즉시 알림 전송
  end
end

Rails.logger.info "Rack::Attack initialized with rate limiting enabled"
