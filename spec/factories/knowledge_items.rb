FactoryBot.define do
  factory :knowledge_item do
    question { "MyText" }
    answer { "MyText" }
    excel_functions { "MyText" }
    code_snippets { "MyText" }
    difficulty { 1 }
    quality_score { "9.99" }
    source { "MyString" }
    tags { "MyText" }
    embedding { "" }
    metadata { "" }
    search_count { 1 }
    use_count { 1 }
    helpful_votes { 1 }
    is_active { false }
    last_used { "2025-07-20 02:35:09" }
  end
end
