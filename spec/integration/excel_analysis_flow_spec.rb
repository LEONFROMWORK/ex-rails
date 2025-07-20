# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Excel Analysis Flow Integration', type: :request do
  let(:user) { create(:user, credits: 100) }
  let(:file_path) { Rails.root.join('spec', 'fixtures', 'test_excel.xlsx') }

  before do
    # Create a simple test Excel file if it doesn't exist
    unless File.exist?(file_path)
      FileUtils.mkdir_p(File.dirname(file_path))

      # Create a minimal Excel file for testing
      package = Axlsx::Package.new
      workbook = package.workbook

      workbook.add_worksheet(name: "Test Sheet") do |sheet|
        sheet.add_row [ "Name", "Age", "Amount" ]
        sheet.add_row [ "John", 25, 1000 ]
        sheet.add_row [ "Jane", "invalid", 2000 ]  # Invalid data type
        sheet.add_row [ "Bob", 30, "not_number" ]  # Invalid data type
      end

      package.serialize(file_path)
    end
  end

  describe 'Complete Excel Analysis Workflow' do
    context 'when user uploads and analyzes an Excel file' do
      it 'successfully processes the file through the entire workflow' do
        # Step 1: Create Excel file record
        excel_file = ExcelFile.create!(
          user: user,
          original_name: 'test_excel.xlsx',
          file_path: file_path.to_s,
          file_size: File.size(file_path),
          content_hash: Digest::SHA256.file(file_path).hexdigest,
          status: 'uploaded'
        )

        expect(excel_file).to be_persisted
        expect(excel_file.status).to eq('uploaded')

        # Step 2: Run Excel analysis
        analyzer = ExcelAnalysis::Services::ErrorAnalyzerService.new(excel_file)
        analysis_result = analyzer.analyze

        expect(analysis_result.success?).to be true
        expect(analysis_result.value[:errors]).to be_an(Array)
        expect(analysis_result.value[:statistics]).to be_a(Hash)

        # Step 3: Check if errors were detected
        errors = analysis_result.value[:errors]
        expect(errors.size).to be > 0

        # Verify error structure
        first_error = errors.first
        expect(first_error).to have_key(:id)
        expect(first_error).to have_key(:type)
        expect(first_error).to have_key(:severity)
        expect(first_error).to have_key(:message)

        # Step 4: Run AI analysis (with mock)
        ai_service = AiIntegration::MultiProvider::AiAnalysisService.new

        # Mock AI provider to avoid API calls
        allow_any_instance_of(Infrastructure::AiProviders::OpenAiProvider)
          .to receive(:generate_response)
          .and_return(Common::Result.success({
            content: {
              "analysis" => {
                "error_1" => {
                  "explanation" => "Data type inconsistency detected",
                  "impact" => "Medium",
                  "root_cause" => "Mixed data types in column",
                  "severity" => "Medium"
                }
              },
              "corrections" => [
                {
                  "cell" => "B3",
                  "original" => "invalid",
                  "corrected" => "0",
                  "explanation" => "Convert invalid text to number",
                  "confidence" => 0.9
                }
              ],
              "overall_confidence" => 0.85,
              "summary" => "Found data type inconsistencies",
              "estimated_time_saved" => "10 minutes"
            }.to_json,
            usage: { total_credits: 150 },
            model: 'gpt-3.5-turbo'
          }))

        ai_result = ai_service.analyze_errors(
          errors: errors,
          file_metadata: { name: excel_file.original_name, size: excel_file.file_size },
          tier: 'tier1',
          user: user
        )

        expect(ai_result.success?).to be true
        expect(ai_result.value[:analysis]).to be_present
        expect(ai_result.value[:corrections]).to be_an(Array)
        expect(ai_result.value[:provider_used]).to eq('openai')

        # Step 5: Create analysis record
        analysis = Analysis.create!(
          excel_file: excel_file,
          user: user,
          detected_errors: errors,
          ai_analysis: ai_result.value[:analysis],
          ai_tier_used: 'tier1',
          tokens_used: ai_result.value[:credits_used]
        )

        expect(analysis).to be_persisted
        expect(analysis.detected_errors).to eq(errors)
        expect(analysis.ai_analysis).to be_present

        # Step 6: Verify user tokens were consumed
        expect { user.consume_tokens!(5) }.not_to raise_error
        expect(user.reload.credits).to eq(95)

        # Step 7: Update Excel file status
        excel_file.update!(status: 'analyzed')
        expect(excel_file.reload.status).to eq('analyzed')
      end
    end

    context 'when AI provider fails' do
      it 'handles the failure gracefully' do
        excel_file = ExcelFile.create!(
          user: user,
          original_name: 'test_excel.xlsx',
          file_path: file_path.to_s,
          file_size: File.size(file_path),
          content_hash: Digest::SHA256.file(file_path).hexdigest,
          status: 'uploaded'
        )

        # Mock AI provider failure
        allow_any_instance_of(AiIntegration::MultiProvider::ProviderManager)
          .to receive(:generate_response)
          .and_return(Common::Result.failure(
            Common::Errors::AIProviderError.new(
              provider: 'all',
              message: 'All AI providers failed'
            )
          ))

        ai_service = AiIntegration::MultiProvider::AiAnalysisService.new
        ai_result = ai_service.analyze_errors(
          errors: [ { type: 'test_error', severity: 'low' } ],
          file_metadata: { name: excel_file.original_name },
          tier: 'tier1',
          user: user
        )

        expect(ai_result.failure?).to be true
        expect(ai_result.error).to be_a(Common::Errors::AIProviderError)
      end
    end

    context 'when user has insufficient tokens' do
      let(:poor_user) { create(:user, credits: 2) }

      it 'rejects AI analysis request' do
        ai_service = AiIntegration::MultiProvider::AiAnalysisService.new

        expect {
          ai_service.analyze_errors(
            errors: [],
            file_metadata: {},
            tier: 'tier1',
            user: poor_user
          )
        }.to raise_error(Common::Errors::InsufficientCreditsError)
      end
    end
  end

  describe 'Payment Integration' do
    context 'when user purchases tokens' do
      it 'successfully processes token purchase flow' do
        payment_handler = PaymentProcessing::Handlers::PaymentHandler.new

        # Mock TossPayments service
        mock_toss_service = instance_double(PaymentProcessing::Services::TossPaymentsService)
        allow(PaymentProcessing::Services::TossPaymentsService).to receive(:new).and_return(mock_toss_service)

        allow(mock_toss_service).to receive(:create_payment).and_return(
          Common::Result.success({
            payment_key: 'test_payment_key',
            checkout_url: 'https://checkout.tosspayments.com/test',
            order_id: 'test_order_id'
          })
        )

        payment_request = PaymentProcessing::Models::PaymentRequest.new(
          user: user,
          amount: 5000,  # 5000 KRW = 50 tokens
          payment_type: 'token_purchase'
        )

        result = payment_handler.create_payment(payment_request)

        expect(result.success?).to be true
        expect(result.value[:payment_url]).to be_present
        expect(result.value[:order_id]).to be_present

        # Verify payment intent was created
        payment_intent = PaymentIntent.find_by(order_id: result.value[:order_id])
        expect(payment_intent).to be_present
        expect(payment_intent.user).to eq(user)
        expect(payment_intent.amount).to eq(5000)
        expect(payment_intent.payment_type).to eq('token_purchase')
      end
    end
  end
end
