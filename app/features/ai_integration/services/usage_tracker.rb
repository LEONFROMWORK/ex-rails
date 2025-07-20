# frozen_string_literal: true

module AiIntegration
  module Services
    class UsageTracker
      PROVIDER_MAP = {
        "openai" => "openai",
        "anthropic" => "anthropic",
        "google" => "google",
        "openrouter" => "openrouter"
      }.freeze

      def initialize(user: nil, session_id: nil)
        @user = user
        @session_id = session_id || SecureRandom.uuid
      end

    def track_usage(
      model_id:,
      provider:,
      cost:,
      input_tokens:,
      output_tokens:,
      request_type: :other,
      prompt: nil,
      response: nil,
      latency_ms: nil,
      request_id: nil,
      metadata: {}
    )
      # Don't track if cost is zero or negative
      return if cost <= 0

      begin
        AiUsageRecord.create_from_api_call(
          model_id: model_id,
          provider: map_provider(provider),
          cost: cost.to_f,
          input_tokens: input_tokens.to_i,
          output_tokens: output_tokens.to_i,
          request_type: request_type.to_s,
          user: @user,
          metadata: build_metadata(metadata, latency_ms, request_id)
        )

        # Log the usage
        Rails.logger.info(
          "AI Usage Tracked: #{model_id} | Cost: $#{cost} | Tokens: #{input_tokens}/#{output_tokens} | Provider: #{provider}"
        )

        # Check budget limits
        check_budget_limits

      rescue => e
        Rails.logger.error("Failed to track AI usage: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      end
    end

    def track_openai_usage(model_id:, response:, prompt: nil, request_type: :chat)
      return unless response.respond_to?(:usage)

      usage = response.usage
      input_tokens = usage.prompt_tokens
      output_tokens = usage.completion_tokens

      # Calculate cost based on model pricing
      cost = calculate_openai_cost(model_id, input_tokens, output_tokens)

      track_usage(
        model_id: model_id,
        provider: "openai",
        cost: cost,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        request_type: request_type,
        prompt: prompt,
        response: response.dig("choices", 0, "message", "content"),
        metadata: {
          model: model_id,
          finish_reason: response.dig("choices", 0, "finish_reason")
        }
      )
    end

    def track_anthropic_usage(model_id:, response:, prompt: nil, request_type: :chat)
      return unless response.respond_to?(:usage)

      usage = response.usage
      input_tokens = usage.input_tokens
      output_tokens = usage.output_tokens

      # Calculate cost based on model pricing
      cost = calculate_anthropic_cost(model_id, input_tokens, output_tokens)

      track_usage(
        model_id: model_id,
        provider: "anthropic",
        cost: cost,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        request_type: request_type,
        prompt: prompt,
        response: response.content&.first&.text,
        metadata: {
          model: model_id,
          stop_reason: response.stop_reason
        }
      )
    end

    def track_google_usage(model_id:, response:, prompt: nil, request_type: :chat)
      # Google AI usage tracking implementation
      # This would depend on the specific Google AI API response format

      # Placeholder implementation
      input_tokens = estimate_tokens(prompt)
      output_tokens = estimate_tokens(response.to_s)
      cost = calculate_google_cost(model_id, input_tokens, output_tokens)

      track_usage(
        model_id: model_id,
        provider: "google",
        cost: cost,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        request_type: request_type,
        prompt: prompt,
        response: response.to_s,
        metadata: {
          model: model_id,
          estimated_tokens: true
        }
      )
    end

    def track_openrouter_usage(model_id:, response:, prompt: nil, request_type: :chat)
      # OpenRouter usage tracking
      # OpenRouter typically provides usage information in the response

      if response.respond_to?(:usage)
        usage = response.usage
        input_tokens = usage.prompt_tokens
        output_tokens = usage.completion_tokens
      else
        # Fallback to estimation
        input_tokens = estimate_tokens(prompt)
        output_tokens = estimate_tokens(response.to_s)
      end

      # Use OpenRouter pricing or estimate
      cost = calculate_openrouter_cost(model_id, input_tokens, output_tokens)

      track_usage(
        model_id: model_id,
        provider: "openrouter",
        cost: cost,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        request_type: request_type,
        prompt: prompt,
        response: response.to_s,
        metadata: {
          model: model_id,
          via_openrouter: true
        }
      )
    end

    def self.get_usage_stats(start_date: 30.days.ago, end_date: Time.current)
      records = AiUsageRecord.by_date_range(start_date, end_date)

      {
        total_cost: records.sum(:cost),
        total_requests: records.count,
        total_tokens: records.sum(:input_tokens) + records.sum(:output_tokens),
        by_provider: records.group(:provider).sum(:cost),
        by_model: records.group(:model_id).sum(:cost),
        daily_usage: records.group_by_day(:created_at).sum(:cost),
        top_models: records.group(:model_id).sum(:cost).sort_by { |_, cost| -cost }.first(5)
      }
    end

    def self.current_month_stats
      records = AiUsageRecord.this_month

      {
        total_cost: records.sum(:cost),
        total_requests: records.count,
        total_tokens: records.sum(:input_tokens) + records.sum(:output_tokens),
        budget_used: AiUsageRecord.budget_utilization_percentage,
        remaining_budget: AiUsageRecord.remaining_budget,
        daily_average: records.sum(:cost) / Date.current.day
      }
    end

    private

    def map_provider(provider)
      PROVIDER_MAP[provider.to_s.downcase] || "other"
    end

    def build_metadata(metadata, latency_ms, request_id)
      base_metadata = {
        session_id: @session_id,
        timestamp: Time.current.iso8601,
        user_id: @user&.id
      }

      base_metadata[:latency_ms] = latency_ms if latency_ms
      base_metadata[:request_id] = request_id if request_id

      base_metadata.merge(metadata)
    end

    def calculate_openai_cost(model_id, input_tokens, output_tokens)
      # OpenAI pricing (per 1M tokens)
      pricing = {
        "gpt-4o-mini" => { input: 0.15, output: 0.60 },
        "gpt-4o" => { input: 5.00, output: 15.00 },
        "gpt-4" => { input: 30.00, output: 60.00 },
        "gpt-3.5-turbo" => { input: 0.50, output: 1.50 }
      }

      model_pricing = pricing[model_id] || pricing["gpt-4o-mini"]

      input_cost = (input_tokens / 1_000_000.0) * model_pricing[:input]
      output_cost = (output_tokens / 1_000_000.0) * model_pricing[:output]

      input_cost + output_cost
    end

    def calculate_anthropic_cost(model_id, input_tokens, output_tokens)
      # Anthropic pricing (per 1M tokens)
      pricing = {
        "claude-3-5-sonnet-20241022" => { input: 3.00, output: 15.00 },
        "claude-3-haiku-20240307" => { input: 0.25, output: 1.25 },
        "claude-3-opus-20240229" => { input: 15.00, output: 75.00 }
      }

      model_pricing = pricing[model_id] || pricing["claude-3-5-sonnet-20241022"]

      input_cost = (input_tokens / 1_000_000.0) * model_pricing[:input]
      output_cost = (output_tokens / 1_000_000.0) * model_pricing[:output]

      input_cost + output_cost
    end

    def calculate_google_cost(model_id, input_tokens, output_tokens)
      # Google AI pricing (per 1M tokens)
      pricing = {
        "gemini-1.5-flash" => { input: 0.075, output: 0.30 },
        "gemini-1.5-pro" => { input: 3.50, output: 10.50 }
      }

      model_pricing = pricing[model_id] || pricing["gemini-1.5-flash"]

      input_cost = (input_tokens / 1_000_000.0) * model_pricing[:input]
      output_cost = (output_tokens / 1_000_000.0) * model_pricing[:output]

      input_cost + output_cost
    end

    def calculate_openrouter_cost(model_id, input_tokens, output_tokens)
      # OpenRouter pricing varies by model
      # This is a simplified version - in practice, you'd fetch current pricing from OpenRouter

      # Use a base pricing that's slightly higher than direct API calls
      case model_id
      when /gpt-4o-mini/
        input_cost = (input_tokens / 1_000_000.0) * 0.20
        output_cost = (output_tokens / 1_000_000.0) * 0.80
      when /gpt-4o/
        input_cost = (input_tokens / 1_000_000.0) * 6.00
        output_cost = (output_tokens / 1_000_000.0) * 18.00
      when /claude-3.5-sonnet/
        input_cost = (input_tokens / 1_000_000.0) * 3.50
        output_cost = (output_tokens / 1_000_000.0) * 17.50
      else
        # Default pricing
        input_cost = (input_tokens / 1_000_000.0) * 1.00
        output_cost = (output_tokens / 1_000_000.0) * 3.00
      end

      input_cost + output_cost
    end

    def estimate_tokens(text)
      return 0 if text.nil? || text.empty?

      # Rough estimation: 1 token ≈ 0.75 words
      # This is a simplification - in practice, you'd use a proper tokenizer
      word_count = text.split.size
      (word_count / 0.75).ceil
    end

    def check_budget_limits
      current_spending = AiUsageRecord.current_month_spending
      monthly_limit = AiUsageRecord.monthly_spending_limit

      utilization = (current_spending / monthly_limit) * 100

      if utilization >= 90
        Rails.logger.warn("AI budget utilization at #{utilization.round(1)}% - approaching limit")
        notify_budget_warning(utilization)
      elsif utilization >= 100
        Rails.logger.error("AI budget limit exceeded! Current spending: $#{current_spending}")
        notify_budget_exceeded(current_spending)
      end
    end

    def notify_budget_warning(utilization)
      # Send warning notification to administrators
      # This could be email, Slack, webhook, etc.
      Rails.logger.info("Budget warning notification sent - #{utilization}% utilization")
    end

    def notify_budget_exceeded(current_spending)
      # Send critical notification to administrators
      # This could be email, Slack, webhook, etc.
      Rails.logger.info("Budget exceeded notification sent - $#{current_spending}")
    end
    end
  end
end
