# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analysis, type: :model do
  let(:user) { create(:user) }
  let(:excel_file) { create(:excel_file, user: user) }

  describe 'associations' do
    it { should belong_to(:excel_file) }
    it { should belong_to(:user) }
  end

  describe 'validations' do
    it { should validate_presence_of(:detected_errors) }
    it { should validate_presence_of(:ai_tier_used) }
    it { should validate_presence_of(:credits_used) }
    it { should validate_numericality_of(:credits_used).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:confidence_score).is_in(0..1).allow_nil }
  end

  describe 'enums' do
    it { should define_enum_for(:ai_tier_used).with_values(rule_based: 0, tier1: 1, tier2: 2) }
    it { should define_enum_for(:status).with_values(pending: 0, processing: 1, completed: 2, failed: 3) }
  end

  describe 'scopes' do
    let!(:analysis1) { create(:analysis, excel_file: excel_file, user: user, created_at: 1.day.ago) }
    let!(:analysis2) { create(:analysis, excel_file: excel_file, user: user, created_at: 2.days.ago) }
    let!(:completed_analysis) { create(:analysis, excel_file: excel_file, user: user, status: :completed) }
    let!(:high_confidence_analysis) { create(:analysis, excel_file: excel_file, user: user, confidence_score: 0.9) }
    let!(:formula_analysis) { create(:analysis, :with_formula_analysis, excel_file: excel_file, user: user) }
    let!(:high_complexity_analysis) { create(:analysis, :high_complexity, excel_file: excel_file, user: user) }
    let!(:circular_ref_analysis) { create(:analysis, :with_circular_references, excel_file: excel_file, user: user) }

    describe '.recent' do
      it 'returns analyses ordered by created_at desc' do
        recent = Analysis.recent
        expect(recent.first).to eq(circular_ref_analysis)
        expect(recent.last).to eq(analysis2)
      end
    end

    describe '.completed' do
      it 'returns only completed analyses' do
        expect(Analysis.completed).to include(completed_analysis)
        expect(Analysis.completed).not_to include(analysis1)
      end
    end

    describe '.high_confidence' do
      it 'returns analyses with confidence >= 0.85' do
        expect(Analysis.high_confidence).to include(high_confidence_analysis)
        # analysis1의 기본 confidence_score는 0.95이므로 포함되어야 함
        expect(Analysis.high_confidence.count).to be >= 1
      end
    end

    describe '.with_formulas' do
      it 'returns analyses with formula_count > 0' do
        expect(Analysis.with_formulas).to include(formula_analysis, high_complexity_analysis)
        expect(Analysis.with_formulas).not_to include(analysis1)
      end
    end

    describe '.high_formula_complexity' do
      it 'returns analyses with complexity >= 3.0' do
        expect(Analysis.high_formula_complexity).to include(high_complexity_analysis)
        expect(Analysis.high_formula_complexity).not_to include(formula_analysis)
      end
    end

    describe '.with_circular_references' do
      it 'returns analyses with circular references' do
        expect(Analysis.with_circular_references).to include(circular_ref_analysis)
        expect(Analysis.with_circular_references).not_to include(analysis1)
      end
    end
  end

  describe 'callbacks' do
    describe '#calculate_counts' do
      it 'calculates error_count from detected_errors' do
        errors = [
          { type: 'formula_error', message: 'Error 1' },
          { type: 'data_error', message: 'Error 2' }
        ]
        analysis = build(:analysis, detected_errors: errors)
        analysis.save!

        expect(analysis.error_count).to eq(2)
      end

      it 'calculates fixed_count from corrections' do
        corrections = [
          { type: 'fix_1', message: 'Fixed 1' },
          { type: 'fix_2', message: 'Fixed 2' },
          { type: 'fix_3', message: 'Fixed 3' }
        ]
        analysis = build(:analysis, corrections: corrections)
        analysis.save!

        expect(analysis.fixed_count).to eq(3)
      end
    end
  end

  describe 'instance methods' do
    describe '#successful?' do
      it 'returns true for completed analysis with errors' do
        errors = Array.new(5) { |i| { type: "error_#{i}", message: "Error #{i}" } }
        analysis = create(:analysis, status: :completed, detected_errors: errors)
        expect(analysis.successful?).to be true
      end

      it 'returns false for completed analysis without errors' do
        analysis = create(:analysis, status: :completed)
        analysis.update_column(:error_count, 0)
        expect(analysis.successful?).to be false
      end

      it 'returns false for non-completed analysis' do
        errors = Array.new(5) { |i| { type: "error_#{i}", message: "Error #{i}" } }
        analysis = create(:analysis, status: :pending, detected_errors: errors)
        expect(analysis.successful?).to be false
      end
    end

    describe '#fix_rate' do
      it 'calculates fix rate correctly' do
        # corrections 배열로 계산되므로 직접 설정
        corrections = Array.new(7) { |i| { type: "fix_#{i}", message: "Fixed #{i}" } }
        errors = Array.new(10) { |i| { type: "error_#{i}", message: "Error #{i}" } }
        analysis = create(:analysis, detected_errors: errors, corrections: corrections)
        expect(analysis.fix_rate).to eq(70.0)
      end

      it 'returns 0 when no errors' do
        # error_count가 0인 분석 생성 후 직접 설정
        analysis = create(:analysis)
        analysis.update_column(:error_count, 0)
        expect(analysis.fix_rate).to eq(0)
      end
    end

    describe '#tier_name' do
      it 'returns correct tier names' do
        tier1_analysis = create(:analysis, ai_tier_used: :tier1)
        tier2_analysis = create(:analysis, ai_tier_used: :tier2)
        rule_based_analysis = create(:analysis, ai_tier_used: :rule_based)

        expect(tier1_analysis.tier_name).to eq('Basic AI (GPT-3.5/Haiku)')
        expect(tier2_analysis.tier_name).to eq('Advanced AI (GPT-4/Opus)')
        expect(rule_based_analysis.tier_name).to eq('Rule-based')
      end
    end

    describe '#estimated_time_saved' do
      it 'calculates estimated time saved' do
        analysis = create(:analysis, fixed_count: 5)
        expect(analysis.estimated_time_saved).to eq(10.0)
      end
    end
  end

  # FormulaEngine 관련 메서드 테스트
  describe 'FormulaEngine analysis methods' do
    describe '#has_formula_analysis?' do
      it 'returns true when formula analysis is present' do
        analysis = create(:analysis, :with_formula_analysis, excel_file: excel_file, user: user)
        expect(analysis.has_formula_analysis?).to be true
      end

      it 'returns false when formula analysis is not present' do
        analysis = create(:analysis)
        expect(analysis.has_formula_analysis?).to be false
      end
    end

    describe '#formula_complexity_level' do
      it 'returns correct complexity levels' do
        low_analysis = create(:analysis, formula_complexity_score: 0.5)
        medium_analysis = create(:analysis, formula_complexity_score: 2.0)
        high_analysis = create(:analysis, formula_complexity_score: 3.5)
        very_high_analysis = create(:analysis, formula_complexity_score: 4.5)
        nil_analysis = create(:analysis, formula_complexity_score: nil)

        expect(low_analysis.formula_complexity_level).to eq('Low')
        expect(medium_analysis.formula_complexity_level).to eq('Medium')
        expect(high_analysis.formula_complexity_level).to eq('High')
        expect(very_high_analysis.formula_complexity_level).to eq('Very High')
        expect(nil_analysis.formula_complexity_level).to eq('Unknown')
      end
    end

    describe '#most_used_functions' do
      it 'returns top 5 most used functions' do
        formula_functions = {
          'function_usage' => [
            { 'name' => 'SUM', 'count' => 10 },
            { 'name' => 'VLOOKUP', 'count' => 8 },
            { 'name' => 'IF', 'count' => 6 },
            { 'name' => 'AVERAGE', 'count' => 4 },
            { 'name' => 'COUNT', 'count' => 3 },
            { 'name' => 'MAX', 'count' => 2 },
            { 'name' => 'MIN', 'count' => 1 }
          ]
        }
        analysis = create(:analysis, formula_functions: formula_functions)

        most_used = analysis.most_used_functions
        expect(most_used.size).to eq(5)
        expect(most_used.first['name']).to eq('SUM')
        expect(most_used.last['name']).to eq('COUNT')
      end

      it 'returns empty array when no formula functions' do
        analysis = create(:analysis, formula_functions: nil)
        expect(analysis.most_used_functions).to eq([])
      end
    end

    describe '#has_circular_references?' do
      it 'returns true when circular references exist' do
        analysis = create(:analysis, :with_circular_references)
        expect(analysis.has_circular_references?).to be true
      end

      it 'returns false when no circular references' do
        analysis = create(:analysis, circular_references: [])
        expect(analysis.has_circular_references?).to be false
      end
    end

    describe '#circular_reference_count' do
      it 'returns correct count of circular references' do
        analysis = create(:analysis, :with_circular_references)
        expect(analysis.circular_reference_count).to eq(1)
      end

      it 'returns 0 when no circular references' do
        analysis = create(:analysis, circular_references: [])
        expect(analysis.circular_reference_count).to eq(0)
      end
    end

    describe '#formula_error_count' do
      it 'returns correct count of formula errors' do
        analysis = create(:analysis, :with_formula_errors)
        expect(analysis.formula_error_count).to eq(2)
      end

      it 'returns 0 when no formula errors' do
        analysis = create(:analysis, formula_errors: [])
        expect(analysis.formula_error_count).to eq(0)
      end
    end

    describe '#optimization_suggestion_count' do
      it 'returns correct count of optimization suggestions' do
        analysis = create(:analysis, :with_optimization_suggestions)
        expect(analysis.optimization_suggestion_count).to eq(2)
      end

      it 'returns 0 when no optimization suggestions' do
        analysis = create(:analysis, formula_optimization_suggestions: [])
        expect(analysis.optimization_suggestion_count).to eq(0)
      end
    end
  end
end
