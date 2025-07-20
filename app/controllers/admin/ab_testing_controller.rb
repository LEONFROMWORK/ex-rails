# frozen_string_literal: true

module Admin
  class AbTestingController < ApplicationController
    before_action :authenticate_admin!
    before_action :load_ab_service

    # 실험 목록
    def index
      @experiments = @ab_service.list_experiments
      @testable_parameters = AiIntegration::Services::AbTestingService::TESTABLE_PARAMETERS
    end

    # 새 실험 생성
    def new
      @experiment = {
        parameter: params[:parameter] || :quality_threshold,
        variants: default_variants_for_parameter(params[:parameter])
      }
    end

    # 실험 생성
    def create
      experiment = @ab_service.create_experiment(
        name: params[:name],
        parameter: params[:parameter].to_sym,
        variants: parse_variants(params[:variants]),
        allocation: params[:allocation]&.to_sym || :random,
        traffic_percentage: params[:traffic_percentage]&.to_i || 100
      )

      flash[:notice] = "실험 '#{experiment[:name]}'이 생성되었습니다."
      redirect_to admin_ab_testing_path(experiment[:id])

    rescue ArgumentError => e
      flash[:error] = "실험 생성 실패: #{e.message}"
      redirect_to new_admin_ab_testing_path(parameter: params[:parameter])
    end

    # 실험 상세보기
    def show
      @experiment_id = params[:id]
      @analysis = @ab_service.analyze_experiment(@experiment_id)

      respond_to do |format|
        format.html
        format.json { render json: @analysis }
      end
    end

    # 실험 종료
    def conclude
      experiment_id = params[:id]
      winner_variant_id = params[:winner_variant_id]

      @ab_service.conclude_experiment(experiment_id, winner_variant_id)

      flash[:notice] = "실험이 종료되고 승자가 적용되었습니다."
      redirect_to admin_ab_testing_index_path
    end

    # 실험 리포트
    def report
      @experiment_id = params[:id]
      @report = @ab_service.generate_report(@experiment_id)

      respond_to do |format|
        format.html
        format.pdf do
          pdf = generate_pdf_report(@report)
          send_data pdf, filename: "ab_test_report_#{@experiment_id}.pdf"
        end
        format.csv do
          csv = generate_csv_report(@report)
          send_data csv, filename: "ab_test_report_#{@experiment_id}.csv"
        end
      end
    end

    # 실시간 메트릭
    def metrics
      experiment_id = params[:id]
      time_range = params[:range] || "24h"

      metrics = fetch_experiment_metrics(experiment_id, time_range)

      render json: metrics
    end

    private

    def load_ab_service
      @ab_service = AiIntegration::Services::AbTestingService.instance
    end

    def default_variants_for_parameter(parameter)
      return [] unless parameter

      config = AiIntegration::Services::AbTestingService::TESTABLE_PARAMETERS[parameter.to_sym]
      return [] unless config

      case config[:type]
      when :float
        # 기본값 주변 3개 변형
        default = config[:default]
        step = (config[:range].max - config[:range].min) / 10.0
        [
          { id: "control", value: default, name: "Control (현재값)" },
          { id: "variant_a", value: (default - step).round(2), name: "Variant A (-10%)" },
          { id: "variant_b", value: (default + step).round(2), name: "Variant B (+10%)" }
        ]
      when :integer
        # 정수값 변형
        default = config[:default]
        [
          { id: "control", value: default, name: "Control" },
          { id: "variant_a", value: default - 1, name: "Variant A" },
          { id: "variant_b", value: default + 1, name: "Variant B" }
        ]
      when :enum
        # 열거형 옵션들
        config[:values].map.with_index do |value, i|
          {
            id: "variant_#{i}",
            value: value,
            name: value.to_s.humanize
          }
        end
      end
    end

    def parse_variants(variants_params)
      return [] unless variants_params

      variants_params.values.map do |variant|
        {
          id: variant[:id],
          value: parse_variant_value(variant[:value]),
          name: variant[:name]
        }
      end
    end

    def parse_variant_value(value)
      # 타입에 따른 값 파싱
      return value.to_f if value.match?(/^\d+\.\d+$/)
      return value.to_i if value.match?(/^\d+$/)
      value
    end

    def fetch_experiment_metrics(experiment_id, time_range)
      # 시간 범위 파싱
      end_time = Time.current
      start_time = case time_range
      when "1h" then 1.hour.ago
      when "24h" then 24.hours.ago
      when "7d" then 7.days.ago
      when "30d" then 30.days.ago
      else 24.hours.ago
      end

      # Redis에서 메트릭 수집
      redis = Redis.new

      experiment = @ab_service.load_experiment(experiment_id)
      return {} unless experiment

      variants_data = experiment[:variants].map do |variant|
        metrics_key = "ab_metrics:#{experiment_id}:#{variant['id']}"
        metrics = redis.hgetall(metrics_key)

        {
          variant_id: variant["id"],
          variant_name: variant["name"],
          variant_value: variant["value"],
          metrics: {
            success_rate: calculate_rate(metrics["success_count"], metrics["failure_count"]),
            avg_quality: safe_average(metrics["quality_sum"], metrics["quality_count"]),
            avg_response_time: safe_average(metrics["response_time_sum"], metrics["response_time_count"]),
            total_cost: metrics["cost_sum"].to_f,
            sample_size: metrics["success_count"].to_i + metrics["failure_count"].to_i
          },
          timeline: fetch_timeline_data(experiment_id, variant["id"], start_time, end_time)
        }
      end

      {
        experiment_id: experiment_id,
        time_range: time_range,
        variants: variants_data,
        statistical_significance: @ab_service.calculate_significance(experiment)
      }
    end

    def calculate_rate(success, failure)
      total = success.to_f + failure.to_f
      return 0 if total == 0
      (success.to_f / total * 100).round(2)
    end

    def safe_average(sum, count)
      return 0 if count.to_i == 0
      (sum.to_f / count.to_i).round(3)
    end

    def authenticate_admin!
      redirect_to root_path unless current_user&.admin?
    end
  end
end
