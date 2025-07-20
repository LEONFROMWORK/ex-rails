# frozen_string_literal: true

module ExcelGeneration
  class TemplatesController < ApplicationController
    before_action :authenticate_user!

    # 템플릿 카테고리 목록
    def index
      begin
        generator = ExcelGeneration::Services::TemplateBasedGenerator.new
        templates_data = generator.list_available_templates

        render json: {
          success: true,
          categories: templates_data[:categories],
          total_templates: templates_data[:total_templates]
        }

      rescue StandardError => e
        Rails.logger.error("Failed to load templates: #{e.message}")
        render_error("템플릿 목록을 불러오는데 실패했습니다", :internal_server_error)
      end
    end

    # 특정 카테고리의 템플릿들
    def category
      category_name = params[:category]

      begin
        generator = ExcelGeneration::Services::TemplateBasedGenerator.new
        templates_data = generator.list_available_templates(category: category_name)

        if templates_data[:error]
          render_error(templates_data[:error], :bad_request)
        else
          render json: {
            success: true,
            category: category_name,
            templates: templates_data[:categories][category_name.to_sym] || [],
            total_templates: templates_data[:total_templates]
          }
        end

      rescue StandardError => e
        Rails.logger.error("Failed to load category templates: #{e.message}")
        render_error("카테고리 템플릿을 불러오는데 실패했습니다", :internal_server_error)
      end
    end

    # 특정 템플릿 상세 정보
    def show
      category_name = params[:category]
      template_name = params[:template_name]

      begin
        generator = ExcelGeneration::Services::TemplateBasedGenerator.new

        # 템플릿 미리보기 생성
        preview_result = generator.generate_template_preview(
          template_name: template_name,
          sample_size: params[:sample_size]&.to_i || 5
        )

        if preview_result[:error]
          render_error("템플릿을 찾을 수 없습니다: #{template_name}", :not_found)
        else
          render json: {
            success: true,
            template_info: preview_result[:template_info],
            columns: preview_result[:columns],
            preview_data: preview_result[:preview_data],
            sample_size: preview_result[:sample_size]
          }
        end

      rescue StandardError => e
        Rails.logger.error("Failed to load template details: #{e.message}")
        render_error("템플릿 상세 정보를 불러오는데 실패했습니다", :internal_server_error)
      end
    end

    # 템플릿 미리보기 (더 큰 샘플)
    def preview
      category_name = params[:category]
      template_name = params[:template_name]
      sample_size = params[:sample_size]&.to_i || 10

      begin
        generator = ExcelGeneration::Services::TemplateBasedGenerator.new

        preview_result = generator.generate_template_preview(
          template_name: template_name,
          sample_size: sample_size
        )

        if preview_result[:error]
          render_error("템플릿 미리보기를 생성할 수 없습니다", :not_found)
        else
          # HTML 테이블 형태로 미리보기 제공
          html_preview = generate_html_preview(preview_result[:preview_data])

          render json: {
            success: true,
            html_preview: html_preview,
            template_info: preview_result[:template_info],
            columns: preview_result[:columns],
            sample_size: preview_result[:sample_size]
          }
        end

      rescue StandardError => e
        Rails.logger.error("Failed to generate template preview: #{e.message}")
        render_error("템플릿 미리보기를 생성하는데 실패했습니다", :internal_server_error)
      end
    end

    private

    def generate_html_preview(preview_data)
      return "" if preview_data.empty?

      headers = preview_data.first
      rows = preview_data[1..-1] || []

      html = "<table class='table table-striped table-hover'>"

      # 헤더
      html += "<thead class='table-dark'><tr>"
      headers.each do |header|
        html += "<th>#{CGI.escapeHTML(header.to_s)}</th>"
      end
      html += "</tr></thead>"

      # 데이터 행들
      html += "<tbody>"
      rows.each do |row|
        html += "<tr>"
        row.each do |cell|
          html += "<td>#{CGI.escapeHTML(cell.to_s)}</td>"
        end
        html += "</tr>"
      end
      html += "</tbody></table>"

      html
    end

    def render_error(message, status)
      render json: {
        success: false,
        error: message
      }, status: status
    end
  end
end
