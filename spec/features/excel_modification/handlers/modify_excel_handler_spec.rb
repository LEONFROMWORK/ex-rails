# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelModification::Handlers::ModifyExcelHandler, type: :handler do
  let(:user) { create(:user, credits: 500) }
  let(:excel_file) { create(:excel_file, user: user) }
  let(:screenshot) { "fake_screenshot_data" }
  let(:user_request) { "A1에 평균 공식을 넣어주세요" }

  let(:handler) do
    described_class.new(
      excel_file: excel_file,
      screenshot: screenshot,
      user_request: user_request,
      user: user
    )
  end

  before do
    # Mock User.system_user
    allow(User).to receive(:system_user).and_return(user)

    # Mock FormulaEngineClient.instance
    formula_engine = instance_double('FormulaEngineClient')
    allow(FormulaEngineClient).to receive(:instance).and_return(formula_engine)
  end

  describe '#execute' do
    context 'with valid inputs' do
      before do
        # Mock the modification service
        allow_any_instance_of(ExcelModification::Services::ExcelModificationService)
          .to receive(:modify_with_ai_suggestions)
          .and_return(
            Common::Result.success({
              modified_file: create(:excel_file, user: user),
              modifications_applied: [
                { 'cell' => 'A1', 'formula' => '=AVERAGE(B1:B10)', 'explanation' => '평균 공식 추가' }
              ],
              download_url: '/download/123',
              preview: { filename: 'modified.xlsx', size: '1.2MB' }
            })
          )
      end

      it 'successfully modifies the Excel file' do
        result = handler.execute

        expect(result).to be_success
        expect(result.value[:modified_file]).to be_present
        expect(result.value[:modifications]).to have(1).item
        expect(result.value[:download_url]).to eq('/download/123')
        expect(result.value[:credits_used]).to be > 0
      end

      it 'deducts credits from user' do
        expect {
          handler.execute
        }.to change { user.reload.credits }.by(-50)
      end
    end

    context 'with invalid inputs' do
      context 'missing screenshot' do
        let(:screenshot) { nil }

        it 'returns validation error' do
          result = handler.execute

          expect(result).to be_failure
          expect(result.error).to be_a(Common::Errors::ValidationError)
          expect(result.error.details[:errors]).to include("Screenshot is required")
        end
      end

      context 'blank user request' do
        let(:user_request) { "" }

        it 'returns validation error' do
          result = handler.execute

          expect(result).to be_failure
          expect(result.error.details[:errors]).to include("User request cannot be blank")
        end
      end
    end

    context 'permission checks' do
      let(:other_user) { create(:user) }
      let(:excel_file) { create(:excel_file, user: other_user) }

      it 'denies access to files not owned by user' do
        result = handler.execute

        expect(result).to be_failure
        expect(result.error).to be_a(Common::Errors::AuthorizationError)
      end
    end

    context 'insufficient credits' do
      let(:user) { create(:user, credits: 10) }

      it 'returns insufficient credits error' do
        result = handler.execute

        expect(result).to be_failure
        expect(result.error).to be_a(Common::Errors::InsufficientCreditsError)
      end
    end
  end
end
