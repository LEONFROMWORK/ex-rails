class AddFormulaAnalysisToAnalyses < ActiveRecord::Migration[8.0]
  def change
    # FormulaEngine 분석 결과를 저장하기 위한 필드들 추가
    add_column :analyses, :formula_analysis, :json # 수식 분석 전체 결과
    add_column :analyses, :formula_complexity_score, :decimal, precision: 5, scale: 2 # 수식 복잡도 점수
    add_column :analyses, :formula_count, :integer, default: 0 # 총 수식 개수
    add_column :analyses, :formula_functions, :json # 사용된 함수 목록과 통계
    add_column :analyses, :formula_dependencies, :json # 수식 의존성 분석 결과
    add_column :analyses, :circular_references, :json # 순환 참조 분석 결과
    add_column :analyses, :formula_errors, :json # 수식 오류 분석 결과
    add_column :analyses, :formula_optimization_suggestions, :json # 수식 최적화 제안

    # 인덱스 추가 (검색 성능 향상)
    add_index :analyses, :formula_complexity_score
    add_index :analyses, :formula_count
  end
end
