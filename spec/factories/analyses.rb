# frozen_string_literal: true

FactoryBot.define do
  factory :analysis do
    association :excel_file
    association :user

    detected_errors do
      [
        {
          type: 'formula_error',
          location: 'A1',
          message: 'Invalid formula: #DIV/0!',
          severity: 'high'
        },
        {
          type: 'data_validation',
          location: 'B2',
          message: 'Value exceeds maximum limit',
          severity: 'medium'
        }
      ]
    end

    ai_analysis do
      {
        summary: 'Found 2 errors in the Excel file',
        recommendations: [
          'Fix formula in cell A1',
          'Update data validation rule in B2'
        ],
        confidence: 0.95,
        processing_time: 12.5
      }
    end

    ai_tier_used { 'tier1' }
    credits_used { 15 }
    confidence_score { 0.95 }

    trait :tier2 do
      ai_tier_used { 'tier2' }
      credits_used { 45 }
      confidence_score { 0.98 }
    end

    trait :low_confidence do
      confidence_score { 0.75 }
    end

    trait :high_credit_usage do
      credits_used { 100 }
    end

    trait :with_many_errors do
      detected_errors do
        10.times.map do |i|
          {
            type: 'formula_error',
            location: "A#{i + 1}",
            message: "Error in cell A#{i + 1}",
            severity: 'medium'
          }
        end
      end
    end

    # FormulaEngine 분석 결과 traits
    trait :with_formula_analysis do
      formula_count { 25 }
      formula_complexity_score { 2.8 }
      formula_analysis do
        {
          summary: { totalFormulas: 25 },
          functions: { details: [] },
          dependencies: { total_dependencies: 18 }
        }
      end

      formula_functions do
        {
          total_functions: 35,
          unique_functions: 12,
          function_usage: [
            { name: 'SUM', count: 8 },
            { name: 'VLOOKUP', count: 5 },
            { name: 'IF', count: 7 },
            { name: 'AVERAGE', count: 3 }
          ],
          categories: {
            'Statistical' => { count: 11, functions: [ { name: 'SUM', count: 8 } ] },
            'Lookup' => { count: 5, functions: [ { name: 'VLOOKUP', count: 5 } ] },
            'Logical' => { count: 7, functions: [ { name: 'IF', count: 7 } ] }
          }
        }
      end

      formula_dependencies do
        {
          total_dependencies: 18,
          direct_dependencies: [
            { from: 'A1', to: 'B1' },
            { from: 'B1', to: 'C1' }
          ],
          indirect_dependencies: [
            { from: 'A1', to: 'C1', path: [ 'A1', 'B1', 'C1' ] }
          ],
          nested_formulas: [
            { cell: 'D1', nesting_level: 3 }
          ]
        }
      end

      circular_references { [] }
      formula_errors { [] }
      formula_optimization_suggestions { [] }
    end

    trait :with_circular_references do
      circular_references do
        [
          {
            cells: [ 'A1', 'B1', 'A1' ],
            chain: [ 'A1 -> B1', 'B1 -> A1' ],
            severity: 'High',
            description: 'A1 → B1 간에 순환 참조가 발생했습니다.'
          }
        ]
      end
    end

    trait :with_formula_errors do
      formula_errors do
        [
          {
            cell: 'A1',
            formula: '=B1/0',
            error_type: 'DIV',
            message: 'Division by zero',
            severity: 'High',
            suggestion: '0으로 나누기 오류입니다. 분모를 확인하세요.'
          },
          {
            cell: 'B2',
            formula: '=C999',
            error_type: 'REF',
            message: 'Invalid reference',
            severity: 'Medium',
            suggestion: '참조된 셀이나 범위가 삭제되었습니다. 참조를 수정하세요.'
          }
        ]
      end
    end

    trait :with_optimization_suggestions do
      formula_optimization_suggestions do
        [
          {
            type: 'complexity_reduction',
            cell: 'A1',
            current_formula: '=IF(AND(B1>0,C1>0),SUM(D1:D10)/COUNT(D1:D10),0)',
            issue: '복잡한 수식이 감지되었습니다.',
            suggestion: '수식을 여러 단계로 나누거나 더 간단한 함수를 사용하는 것을 고려하세요.',
            priority: 'Medium'
          },
          {
            type: 'function_upgrade',
            cell: 'B1',
            current_formula: '=VLOOKUP(A1,Data!A:B,2,FALSE)',
            issue: 'VLOOKUP 함수가 사용되었습니다.',
            suggestion: '더 강력하고 유연한 XLOOKUP 함수 사용을 고려하세요.',
            priority: 'Low'
          }
        ]
      end
    end

    trait :high_complexity do
      formula_complexity_score { 4.2 }
      formula_count { 50 }
    end

    trait :low_complexity do
      formula_complexity_score { 0.8 }
      formula_count { 5 }
    end
  end
end
