# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI System Integration', type: :integration do
  let(:user) { create(:user, :pro, credits: 500) }
  let(:excel_file) { create(:excel_file, user: user) }

  before do
    # Mock AI providers to avoid external API calls
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
      mock_ai_response
    )
  end

  describe 'Excel Analysis with AI Integration' do
    context 'with 2-tier AI analysis system' do
      it 'processes file through complete analysis pipeline' do
        # Create handler for analysis
        handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
          excel_file: excel_file,
          user: user
        )

        # Execute analysis
        result = handler.execute

        expect(result).to be_success
        expect(result.value).to include(:message, :analysis_id, :errors_found, :ai_tier_used, :credits_used)

        # Verify file status updated
        excel_file.reload
        expect(excel_file.status).to eq('analyzed')

        # Verify analysis record created
        analysis = excel_file.latest_analysis
        expect(analysis).to be_present
        expect(analysis.ai_tier_used).to be_present
        expect(analysis.credits_used).to be > 0
      end

      it 'escalates to tier 2 when confidence is low' do
        # Mock low confidence tier 1 response
        allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
          mock_ai_response(confidence: 0.6),
          mock_ai_response(confidence: 0.95, tier: 2)
        )

        handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
          excel_file: excel_file,
          user: user
        )

        result = handler.execute
        expect(result).to be_success

        analysis = excel_file.reload.latest_analysis
        expect(analysis.ai_tier_used).to eq(2)
        expect(analysis.credits_used).to be > 100 # Should use more tokens for tier 2
      end

      it 'handles insufficient tokens gracefully' do
        user.update!(credits: 2) # Not enough for any tier

        handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
          excel_file: excel_file,
          user: user
        )

        result = handler.execute
        expect(result).to be_failure
        expect(result.error).to include('Insufficient tokens')
      end
    end

    context 'with AI response validation' do
      it 'validates AI responses before processing' do
        # Mock invalid AI response
        allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
          {
            'message' => 'Test response',
            'confidence_score' => 1.5, # Invalid confidence score
            'tokens_used' => 100,
            'provider' => 'openai'
          }
        )

        handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
          excel_file: excel_file,
          user: user
        )

        expect { handler.execute }.to raise_error(/invalid responses/)
      end

      it 'sanitizes AI responses with harmful content' do
        # Mock response with harmful content
        allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
          {
            'message' => 'Analysis complete <script>alert("xss")</script>',
            'confidence_score' => 0.85,
            'tokens_used' => 100,
            'provider' => 'openai'
          }
        )

        validator = Ai::ResponseValidation::AiResponseValidator.new(
          {
            'message' => 'Analysis complete <script>alert("xss")</script>',
            'confidence_score' => 0.85,
            'tokens_used' => 100,
            'provider' => 'openai'
          }
        )

        result = validator.validate
        expect(result).to be_success
        expect(result.value['message']).not_to include('<script>')
      end
    end

    context 'with AI response caching' do
      let(:cache_service) { Ai::ResponseCache.new }

      before do
        cache_service.clear_all
      end

      it 'caches and retrieves AI responses' do
        # First request - should hit AI provider
        service1 = Ai::MultiProviderService.new(tier: 1)
        result1 = service1.chat(
          message: 'Analyze this Excel file',
          user: user
        )

        # Second identical request - should hit cache
        service2 = Ai::MultiProviderService.new(tier: 1)
        result2 = service2.chat(
          message: 'Analyze this Excel file',
          user: user
        )

        expect(result1).to eq(result2)

        # Verify cache statistics
        stats = cache_service.stats
        expect(stats[:hits]).to be >= 1
      end

      it 'does not cache low confidence responses' do
        response = {
          'message' => 'Low confidence response',
          'confidence_score' => 0.5, # Below threshold
          'tokens_used' => 50,
          'provider' => 'openai'
        }

        result = cache_service.set('test_key', response)
        expect(result).to be false

        cached = cache_service.get('test_key')
        expect(cached).to be_nil
      end
    end
  end

  describe 'Chat System Integration' do
    let(:conversation) { create(:chat_conversation, user: user, excel_file: excel_file) }

    it 'processes chat messages with file context' do
      handler = Ai::Handlers::ChatHandler.new(
        user: user,
        message: 'What errors are in this file?',
        conversation_id: conversation.id,
        file_id: excel_file.id
      )

      result = handler.execute
      expect(result).to be_success

      # Verify message was created
      chat_message = conversation.reload.chat_messages.last
      expect(chat_message.content).to be_present
      expect(chat_message.ai_tier_used).to be_present
      expect(chat_message.credits_used).to be > 0

      # Verify user tokens were consumed
      user.reload
      expect(user.credits).to be < 500
    end

    it 'handles chat feedback system' do
      # Create a chat message first
      chat_message = create(:chat_message,
        chat_conversation: conversation,
        user: user,
        role: 'assistant',
        ai_tier_used: 1,
        tokens_used: 50,
        provider: 'openai'
      )

      handler = Ai::Handlers::FeedbackHandler.new(
        user: user,
        chat_message_id: chat_message.id,
        rating: 4,
        feedback_text: 'Very helpful response'
      )

      result = handler.execute
      expect(result).to be_success

      # Verify feedback was recorded
      feedback = AiFeedback.last
      expect(feedback.rating).to eq(4)
      expect(feedback.feedback_text).to eq('Very helpful response')
      expect(feedback.user).to eq(user)
      expect(feedback.chat_message).to eq(chat_message)
    end
  end

  describe 'Multi-Provider Fallback System' do
    it 'falls back to secondary providers when primary fails' do
      # Mock first provider failure, second provider success
      allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_raise(
        StandardError.new('Provider unavailable')
      ).once

      allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
        mock_ai_response
      ).once

      service = Ai::MultiProviderService.new(tier: 1)
      result = service.chat(message: 'Test message', user: user)

      expect(result).to be_present
      expect(result['message']).to be_present
    end

    it 'raises error when all providers fail' do
      # Mock all providers failing
      allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_raise(
        StandardError.new('All providers unavailable')
      )

      service = Ai::MultiProviderService.new(tier: 1)

      expect {
        service.chat(message: 'Test message', user: user)
      }.to raise_error(/All AI providers failed/)
    end
  end

  describe 'Performance and Error Handling' do
    it 'handles large Excel files efficiently' do
      # Create a large file simulation
      large_file = create(:excel_file, user: user, file_size: 25.megabytes)

      handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
        excel_file: large_file,
        user: user
      )

      start_time = Time.current
      result = handler.execute
      end_time = Time.current

      expect(result).to be_success
      expect(end_time - start_time).to be < 30.seconds # Should complete within 30s
    end

    it 'handles concurrent analysis requests' do
      # Create multiple files
      files = 3.times.map { create(:excel_file, user: user) }

      # Process them concurrently
      threads = files.map do |file|
        Thread.new do
          handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
            excel_file: file,
            user: user
          )
          handler.execute
        end
      end

      results = threads.map(&:value)

      # All should succeed
      results.each do |result|
        expect(result).to be_success
      end

      # Verify all files were processed
      files.each do |file|
        file.reload
        expect(file.status).to eq('analyzed')
      end
    end

    it 'handles network timeouts gracefully' do
      # Mock network timeout
      allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_raise(
        Net::ReadTimeout.new('Request timeout')
      )

      service = Ai::MultiProviderService.new(tier: 1)

      expect {
        service.chat(message: 'Test message', user: user)
      }.to raise_error(/All AI providers failed/)
    end
  end

  private

  def mock_ai_response(confidence: 0.85, tier: 1)
    {
      'message' => 'Analysis completed successfully. Found 2 errors in the Excel file.',
      'confidence_score' => confidence,
      'tokens_used' => tier == 1 ? 100 : 250,
      'provider' => tier == 1 ? 'openai' : 'anthropic',
      'structured_analysis' => {
        'errors_found' => 2,
        'warnings_found' => 1,
        'optimizations_suggested' => 3
      }
    }
  end
end
