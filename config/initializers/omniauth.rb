require_relative "../../lib/omniauth/strategies/kakao"

Rails.application.config.middleware.use OmniAuth::Builder do
  # Google OAuth2
  provider :google_oauth2,
           ENV["GOOGLE_CLIENT_ID"],
           ENV["GOOGLE_CLIENT_SECRET"],
           {
             scope: "email,profile",
             prompt: "select_account",
             image_aspect_ratio: "square",
             image_size: 200,
             access_type: "offline",
             skip_jwt: true
           }

  # Kakao OAuth2
  provider :kakao,
           ENV["KAKAO_CLIENT_ID"],
           ENV["KAKAO_CLIENT_SECRET"]
end

OmniAuth.config.allowed_request_methods = [ :post, :get ]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.logger = Rails.logger

# Handle OmniAuth failures
OmniAuth.config.on_failure = Proc.new do |env|
  Auth::SessionsController.action(:failure).call(env)
end
