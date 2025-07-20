require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class Kakao < OmniAuth::Strategies::OAuth2
      option :name, "kakao"

      option :client_options, {
        site: "https://kapi.kakao.com",
        authorize_url: "https://kauth.kakao.com/oauth/authorize",
        token_url: "https://kauth.kakao.com/oauth/token"
      }

      uid { raw_info["id"].to_s }

      info do
        {
          name: properties["nickname"],
          email: kakao_account["email"],
          image: properties["profile_image"],
          verified: kakao_account["is_email_verified"]
        }
      end

      extra do
        {
          properties: properties,
          kakao_account: kakao_account
        }
      end

      def callback_url
        full_host + script_name + callback_path
      end

      def raw_info
        @raw_info ||= access_token.get("/v2/user/me").parsed
      end

      private

      def properties
        @properties ||= raw_info["properties"] || {}
      end

      def kakao_account
        @kakao_account ||= raw_info["kakao_account"] || {}
      end
    end
  end
end
