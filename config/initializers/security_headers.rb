# frozen_string_literal: true

# 추가 보안 헤더 설정
Rails.application.configure do
  # HTTP Strict Transport Security (HSTS) 설정
  config.ssl_options = {
    hsts: {
      expires: 1.year,
      subdomains: true,
      preload: true
    }
  }

  # 미들웨어를 통한 보안 헤더 설정
  config.middleware.use Rack::Protection::StrictTransport if Rails.env.production?
end

# ApplicationController에 보안 헤더 설정을 추가하는 초기화 파일
Rails.application.config.to_prepare do
  ApplicationController.class_eval do
    before_action :set_security_headers

    private

    def set_security_headers
      # X-Frame-Options: 클릭재킹 방지
      response.headers["X-Frame-Options"] = "SAMEORIGIN"

      # X-Content-Type-Options: MIME 타입 스니핑 방지
      response.headers["X-Content-Type-Options"] = "nosniff"

      # X-XSS-Protection: XSS 필터 활성화 (레거시 브라우저용)
      response.headers["X-XSS-Protection"] = "1; mode=block"

      # Referrer-Policy: 리퍼러 정보 제한
      response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

      # Permissions-Policy: 브라우저 기능 제한
      permissions = [
        "camera=(), microphone=(), payment=(), usb=()",
        "magnetometer=(), gyroscope=(), speaker=()",
        "vibrate=(), fullscreen=(self), picture-in-picture=()"
      ].join(", ")
      response.headers["Permissions-Policy"] = permissions

      # Cross-Origin-Embedder-Policy: 임베딩 제한
      response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"

      # Cross-Origin-Opener-Policy: 윈도우 컨텍스트 분리
      response.headers["Cross-Origin-Opener-Policy"] = "same-origin"

      # Cross-Origin-Resource-Policy: 리소스 공유 제한
      response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
    end
  end
end
