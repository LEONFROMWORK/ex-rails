# frozen_string_literal: true

# Vertical Slice controller for Excel Generation domain
# Follows Single Responsibility Principle (SRP) - only handles Excel generation requests
class ExcelGenerationController < ApplicationController
  before_action :authenticate_user!

  # Generate Excel from template
  def generate_from_template
    command = ExcelGeneration::Commands::GenerateFromTemplate.new.tap do |cmd|
      cmd.template_name = params[:template_name]
      cmd.template_data = params[:template_data] || {}
      cmd.user_id = current_user.id
      cmd.customizations = params[:customizations] || {}
      cmd.output_filename = params[:filename]
    end

    result = command.call

    if result.success?
      render json: {
        success: true,
        file_id: result.value[:file_id],
        file_path: result.value[:file_path],
        file_size: result.value[:file_size],
        generation_time: result.value[:generation_time],
        download_url: download_generated_file_url(result.value[:file_id])
      }
    else
      render json: {
        success: false,
        error: result.error
      }, status: :unprocessable_entity
    end
  end

  # Generate Excel from conversation
  def generate_from_conversation
    command = ExcelGeneration::Commands::GenerateFromConversation.new.tap do |cmd|
      cmd.conversation_data = params[:conversation_data] || {}
      cmd.user_id = current_user.id
      cmd.output_filename = params[:filename]
    end

    result = command.call

    if result.success?
      render json: {
        success: true,
        file_id: result.value[:file_id],
        file_path: result.value[:file_path],
        file_size: result.value[:file_size],
        generation_time: result.value[:generation_time],
        template_structure: result.value[:template_structure],
        requirements_analyzed: result.value[:requirements_analyzed],
        download_url: download_generated_file_url(result.value[:file_id])
      }
    else
      render json: {
        success: false,
        error: result.error
      }, status: :unprocessable_entity
    end
  end

  # List available templates
  def list_templates
    query = ExcelGeneration::Queries::ListTemplates.new.tap do |q|
      q.category = params[:category]
      q.user_tier = current_user.subscription_tier
    end

    result = query.call

    if result.success?
      render json: {
        success: true,
        templates: result.value[:templates],
        categories: result.value[:categories],
        total_count: result.value[:total_count]
      }
    else
      render json: {
        success: false,
        error: result.error
      }, status: :unprocessable_entity
    end
  end

  private

  def download_generated_file_url(file_id)
    # This would be implemented based on your file serving strategy
    api_v1_file_download_path(file_id)
  end
end
