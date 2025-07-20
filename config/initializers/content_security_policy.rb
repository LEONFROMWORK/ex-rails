# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    # 기본 소스: 자신의 도메인과 HTTPS만 허용
    policy.default_src :self, :https

    # 폰트: Google Fonts, Pretendard 및 데이터 URI 허용
    policy.font_src :self, :https, :data, "https://fonts.googleapis.com", "https://fonts.gstatic.com", "https://cdn.jsdelivr.net"

    # 이미지: 자신의 도메인, HTTPS, 데이터 URI, Blob 허용
    policy.img_src :self, :https, :data, :blob

    # 객체: 완전 차단 (Flash, Java 등)
    policy.object_src :none

    # 스크립트: 자신의 도메인, HTTPS, 인라인 스크립트용 nonce
    # unsafe-eval은 Vue.js template compilation에 필요
    policy.script_src :self, :https, :unsafe_eval, "https://cdn.jsdelivr.net"
    # Allow @vite/client to hot reload javascript changes in development
    #    policy.script_src *policy.script_src, :unsafe_eval, "http://#{ ViteRuby.config.host_with_port }" if Rails.env.development?

    # You may need to enable this in production as well depending on your setup.
    #    policy.script_src *policy.script_src, :blob if Rails.env.test?


    # 스타일: 자신의 도메인, HTTPS, 인라인 스타일, Google Fonts, Pretendard
    policy.style_src :self, :https, :unsafe_inline, "https://fonts.googleapis.com", "https://cdn.jsdelivr.net"
    # Allow @vite/client to hot reload style changes in development
    #    policy.style_src *policy.style_src, :unsafe_inline if Rails.env.development?


    # 웹소켓: ActionCable 지원 및 Formula Engine
    if Rails.env.production?
      policy.connect_src :self, :https, :wss, ENV.fetch("FORMULA_ENGINE_URL", "")
    else
      policy.connect_src :self, :https, :wss, "ws://localhost:*", "wss://localhost:*", "http://localhost:3002"
    end
    # Allow @vite/client to hot reload changes in development
    #    policy.connect_src *policy.connect_src, "ws://#{ ViteRuby.config.host_with_port }" if Rails.env.development?


    # 프레임: 동일 출처만 허용
    policy.frame_src :self

    # 미디어: 자신의 도메인과 HTTPS만 허용
    policy.media_src :self, :https

    # 워커: 자신의 도메인만 허용
    policy.worker_src :self, :blob

    # 매니페스트: PWA 지원
    policy.manifest_src :self

    # Base URI: 자신의 도메인만 허용
    policy.base_uri :self

    # Form Action: 자신의 도메인과 HTTPS만 허용
    policy.form_action :self, :https

    # 프레임 조상: 동일 출처만 허용
    policy.frame_ancestors :self

    # Violation 보고 (프로덕션에서 활성화)
    if Rails.env.production?
      policy.report_uri "/csp-violation-report-endpoint"
    end
  end

  # Generate session nonces for permitted importmap, inline scripts, and inline styles.
  config.content_security_policy_nonce_generator = ->(request) {
    SecureRandom.base64(16)
  }
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # 개발 환경에서는 리포트 모드로 실행
  if Rails.env.development?
    config.content_security_policy_report_only = true
  end

  # 추가 보안 헤더 설정
  config.force_ssl = Rails.env.production?

  # XSS 보호
  config.content_security_policy do |policy|
    policy.upgrade_insecure_requests if Rails.env.production?
  end
end
