# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'User Registration', type: :system do
  before do
    driven_by(:headless_chrome)
  end

  describe 'Sign up process' do
    it 'allows new user to register' do
      visit new_user_registration_path

      within('#new_user') do
        fill_in 'Name', with: 'Test User'
        fill_in 'Email', with: 'test@example.com'
        fill_in 'Password', with: 'password123'
        fill_in 'Password confirmation', with: 'password123'
        click_button 'Sign up'
      end

      expect(page).to have_content('Welcome! You have signed up successfully')
      expect(current_path).to eq(root_path)
    end

    it 'prevents registration with invalid email' do
      visit new_user_registration_path

      within('#new_user') do
        fill_in 'Name', with: 'Test User'
        fill_in 'Email', with: 'invalid-email'
        fill_in 'Password', with: 'password123'
        fill_in 'Password confirmation', with: 'password123'
        click_button 'Sign up'
      end

      expect(page).to have_content('Email is invalid')
    end

    it 'prevents registration with weak password' do
      visit new_user_registration_path

      within('#new_user') do
        fill_in 'Name', with: 'Test User'
        fill_in 'Email', with: 'test@example.com'
        fill_in 'Password', with: '123'
        fill_in 'Password confirmation', with: '123'
        click_button 'Sign up'
      end

      expect(page).to have_content('Password is too short')
    end
  end

  describe 'Sign in process' do
    let(:user) { create(:user, password: 'password123') }

    it 'allows user to sign in with valid credentials' do
      visit new_user_session_path

      within('#new_user') do
        fill_in 'Email', with: user.email
        fill_in 'Password', with: 'password123'
        click_button 'Log in'
      end

      expect(page).to have_content('Signed in successfully')
      expect(current_path).to eq(root_path)
    end

    it 'prevents sign in with invalid credentials' do
      visit new_user_session_path

      within('#new_user') do
        fill_in 'Email', with: user.email
        fill_in 'Password', with: 'wrongpassword'
        click_button 'Log in'
      end

      expect(page).to have_content('Invalid Email or password')
    end
  end
end
