class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # FormulaEngine 헬퍼 메소드를 모든 모델에서 사용 가능하도록 포함
  include FormulaEngineHelper
end
