# frozen_string_literal: true

module Auth
  class SessionsController < ApplicationController
    skip_before_action :authenticate_user!, only: [ :new, :create, :omniauth, :failure ]
    skip_before_action :verify_authenticity_token, only: [ :omniauth ]

    def new
      redirect_to root_path if user_signed_in?
    end

    def create
      user = User.find_by(email: params[:email]&.downcase)

      if user&.authenticate(params[:password])
        login(user)
        redirect_to root_path, notice: "Welcome back, #{user.name}!"
      else
        flash.now[:alert] = "Invalid email or password"
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      logout
      redirect_to root_path, notice: "Successfully logged out"
    end

    # OAuth callback
    def omniauth
      auth = request.env["omniauth.auth"]
      user = User.from_omniauth(auth)

      if user.persisted?
        login(user)
        redirect_to root_path, notice: "Successfully logged in with #{auth.provider.capitalize}!"
      else
        redirect_to new_auth_session_path, alert: "There was an error logging you in. Please try again."
      end
    end

    # OAuth failure callback
    def failure
      redirect_to new_auth_session_path, alert: "Authentication failed. Please try again."
    end
  end
end
