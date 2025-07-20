# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: [ :show, :edit, :update, :destroy ]

    def index
      @users = User.all.order(created_at: :desc)
    end

    def show
    end

    # User creation disabled - only OAuth login allowed
    def new
      redirect_to admin_users_path, alert: "새 사용자 추가 기능은 비활성화되었습니다."
    end

    def create
      redirect_to admin_users_path, alert: "새 사용자 추가 기능은 비활성화되었습니다."
    end

    def edit
    end

    def update
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "User was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path, notice: "User was successfully deleted."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation, :role, :tier, :credits)
    end
  end
end
