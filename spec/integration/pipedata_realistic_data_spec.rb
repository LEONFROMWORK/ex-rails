# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PipeData Realistic Data Integration', type: :request do
  let(:valid_token) { 'test_pipedata_token' }

  before do
    allow(Rails.application.credentials).to receive(:pipedata_api_token).and_return(valid_token)
    allow(ENV).to receive(:[]).with('PIPEDATA_API_TOKEN').and_return(valid_token)
  end

  describe '실제 PipeData 형식 시뮬레이션' do
    context 'Stack Overflow 데이터 형식' do
      let(:stackoverflow_sample_data) do
        {
          data: [
            {
              question: "Excel에서 VLOOKUP 함수 사용 시 #REF! 오류가 발생합니다. 어떻게 해결하나요?",
              answer: "#REF! 오류는 VLOOKUP 함수의 열 번호가 테이블 범위를 벗어났을 때 발생합니다.\n\n**해결 방법:**\n\n1. **열 번호 확인**: 테이블의 실제 열 개수보다 큰 번호를 사용했는지 확인\n   ```excel\n   =VLOOKUP(A1, B:D, 4, FALSE)  // 잘못됨: B:D는 3개 열만 있음\n   =VLOOKUP(A1, B:D, 3, FALSE)  // 올바름\n   ```\n\n2. **절대 참조 사용**: 수식을 복사할 때 테이블 범위가 변경되지 않도록\n   ```excel\n   =VLOOKUP(A1, $B$1:$D$100, 3, FALSE)\n   ```\n\n3. **테이블 구조 변경 시 주의**: 열 삭제/삽입 후 VLOOKUP 수식 업데이트 필요",
              difficulty: "medium",
              quality_score: 9.1,
              source: "pipedata_stackoverflow",
              excel_functions: [ "VLOOKUP" ],
              code_snippets: [
                "=VLOOKUP(A1, B:D, 3, FALSE)",
                "=VLOOKUP(A1, $B$1:$D$100, 3, FALSE)"
              ],
              tags: [ "excel", "vlookup", "ref-error", "troubleshooting" ],
              metadata: {
                stackoverflow_id: "45123789",
                question_score: 78,
                answer_score: 156,
                view_count: 23456,
                answer_count: 8,
                accepted_answer: true,
                created_date: "2023-03-15T10:30:00Z",
                last_activity: "2023-03-20T14:22:00Z",
                tags_original: [ "excel", "vlookup", "error-handling" ],
                author: {
                  display_name: "ExcelGuru2023",
                  reputation: 15430,
                  user_type: "registered"
                },
                bounty_amount: null,
                community_owned: false
              }
            },
            {
              question: "Excel 피벗 테이블에서 날짜 필드가 자동으로 그룹화됩니다. 이를 방지하는 방법은?",
              answer: "Excel 2016 이후 버전에서는 날짜/시간 필드가 자동으로 그룹화되는 기능이 기본 활성화되어 있습니다.\n\n**자동 그룹화 비활성화 방법:**\n\n### 전역 설정 변경:\n1. 파일 → 옵션 → 데이터\n2. '피벗 테이블에서 자동으로 날짜/시간 열 감지' 체크 해제\n\n### 개별 피벗 테이블 설정:\n1. 피벗 테이블 선택\n2. 분석/피벗 테이블 도구 → 옵션\n3. '자동으로 날짜/시간 열 감지' 체크 해제\n\n### 이미 그룹화된 경우:\n1. 날짜 필드 우클릭\n2. '그룹 해제' 선택\n\n**주의사항**: 이 설정은 새로 만드는 피벗 테이블에만 적용됩니다.",
              difficulty: "easy",
              quality_score: 8.7,
              source: "pipedata_stackoverflow",
              excel_functions: [ "PIVOT_TABLE" ],
              code_snippets: [],
              tags: [ "excel", "pivot-table", "date-grouping", "auto-detect" ],
              metadata: {
                stackoverflow_id: "67890123",
                question_score: 45,
                answer_score: 89,
                view_count: 12890,
                answer_count: 5,
                accepted_answer: true,
                created_date: "2023-08-22T09:15:00Z",
                last_activity: "2023-08-25T16:45:00Z",
                tags_original: [ "excel", "pivot-table", "date" ],
                author: {
                  display_name: "DataAnalyst_Pro",
                  reputation: 8920,
                  user_type: "registered"
                },
                bounty_amount: 50,
                community_owned: false
              }
            }
          ]
        }
      end

      it 'Stack Overflow 형식 데이터를 정확히 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        post '/api/v1/pipedata', params: stackoverflow_sample_data, headers: headers

        expect(response).to have_http_status(:ok)

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(2)
        expect(response_body['processed']).to eq(2)

        # 첫 번째 아이템 (VLOOKUP 관련) 검증
        vlookup_item = KnowledgeItem.find_by("question LIKE ?", "%VLOOKUP%")
        expect(vlookup_item).to be_present
        expect(vlookup_item.source).to eq("pipedata_stackoverflow")
        expect(vlookup_item.difficulty).to eq(1) # medium
        expect(vlookup_item.quality_score).to eq(9.1)
        expect(vlookup_item.excel_functions).to include("VLOOKUP")
        expect(vlookup_item.code_snippets).to have(2).items
        expect(vlookup_item.tags).to include("excel", "vlookup", "ref-error", "troubleshooting")

        # 메타데이터 상세 검증
        expect(vlookup_item.metadata['stackoverflow_id']).to eq("45123789")
        expect(vlookup_item.metadata['question_score']).to eq(78)
        expect(vlookup_item.metadata['view_count']).to eq(23456)
        expect(vlookup_item.metadata['accepted_answer']).to be true
        expect(vlookup_item.metadata['author']['display_name']).to eq("ExcelGuru2023")
        expect(vlookup_item.metadata['author']['reputation']).to eq(15430)

        # 두 번째 아이템 (피벗 테이블 관련) 검증
        pivot_item = KnowledgeItem.find_by("question LIKE ?", "%피벗 테이블%")
        expect(pivot_item).to be_present
        expect(pivot_item.difficulty).to eq(0) # easy
        expect(pivot_item.quality_score).to eq(8.7)
        expect(pivot_item.excel_functions).to include("PIVOT_TABLE")
        expect(pivot_item.metadata['bounty_amount']).to eq(50)
      end
    end

    context 'Reddit 데이터 형식' do
      let(:reddit_sample_data) do
        {
          data: [
            {
              question: "Excel 초보입니다. SUMIFS와 SUMIF의 차이점이 뭔가요?",
              answer: "좋은 질문이네요! 둘 다 조건부 합계를 구하는 함수지만 중요한 차이가 있어요.\n\n**SUMIF**: 단일 조건\n- 문법: `=SUMIF(범위, 조건, 합계범위)`\n- 예시: `=SUMIF(A:A, \">100\", B:B)` → A열이 100보다 큰 행의 B열 합계\n\n**SUMIFS**: 다중 조건 (Excel 2007+)\n- 문법: `=SUMIFS(합계범위, 조건범위1, 조건1, 조건범위2, 조건2, ...)`\n- 예시: `=SUMIFS(C:C, A:A, \">100\", B:B, \"완료\")` → A열 > 100 AND B열 = \"완료\"인 행의 C열 합계\n\n**팁**: SUMIFS는 조건을 여러 개 걸 수 있어서 더 유연해요. SUMIF로 할 수 있는 건 SUMIFS로도 다 할 수 있습니다!\n\n도움이 되셨나요? 더 궁금한 거 있으면 언제든 물어보세요 😊",
              difficulty: "easy",
              quality_score: 8.3,
              source: "pipedata_reddit",
              excel_functions: [ "SUMIF", "SUMIFS" ],
              code_snippets: [
                "=SUMIF(A:A, \">100\", B:B)",
                "=SUMIFS(C:C, A:A, \">100\", B:B, \"완료\")"
              ],
              tags: [ "excel", "sumif", "sumifs", "beginner", "conditional-sum" ],
              metadata: {
                reddit_post_id: "1a2b3c4d",
                subreddit: "excel",
                upvotes: 127,
                downvotes: 8,
                comment_count: 23,
                awards: [
                  { name: "Silver", count: 2 },
                  { name: "Helpful", count: 1 }
                ],
                created_utc: 1692784230,
                edited: false,
                gilded: 0,
                distinguished: null,
                stickied: false,
                over_18: false,
                spoiler: false,
                flair: {
                  text: "solved",
                  css_class: "flair-solved"
                },
                author: {
                  name: "helpful_excel_user",
                  is_premium: false,
                  comment_karma: 5420,
                  link_karma: 890
                },
                op_confirmed_solution: true
              }
            },
            {
              question: "회사에서 엑셀로 재고 관리하는데, 자동으로 부족한 품목 알림받는 방법 있나요?",
              answer: "재고 관리 자동화는 정말 유용하죠! 몇 가지 방법이 있어요:\n\n## 1. 조건부 서식으로 시각적 알림\n- 재고량 열 선택\n- 홈 → 조건부 서식 → 새 규칙\n- \"다음을 포함하는 셀만 서식 지정\" 선택\n- 셀 값이 \"작거나 같음\" 최소재고량\n- 빨간색 배경 설정\n\n## 2. IF 함수로 알림 메시지\n```excel\n=IF(C2<=D2, \"주문 필요: \"&A2, \"충분\")\n```\n(C2: 현재고, D2: 최소재고, A2: 품목명)\n\n## 3. 필터로 부족 품목만 보기\n- 데이터 → 필터\n- 상태 열에서 \"주문 필요\"만 필터링\n\n## 4. 고급: VBA로 이메일 자동 발송\n(이건 좀 복잡하니 필요하면 따로 설명드릴게요)\n\n어떤 방법이 가장 관심 있으세요?",
              difficulty: "medium",
              quality_score: 9.0,
              source: "pipedata_reddit",
              excel_functions: [ "IF", "CONDITIONAL_FORMATTING", "FILTER" ],
              code_snippets: [
                "=IF(C2<=D2, \"주문 필요: \"&A2, \"충분\")"
              ],
              tags: [ "excel", "inventory", "automation", "conditional-formatting", "business" ],
              metadata: {
                reddit_post_id: "5e6f7g8h",
                subreddit: "excel",
                upvotes: 234,
                downvotes: 12,
                comment_count: 45,
                awards: [
                  { name: "Gold", count: 1 },
                  { name: "Helpful", count: 3 },
                  { name: "Wholesome", count: 1 }
                ],
                created_utc: 1692890145,
                edited: true,
                edited_utc: 1692891200,
                gilded: 1,
                distinguished: null,
                stickied: false,
                over_18: false,
                spoiler: false,
                flair: {
                  text: "discussion",
                  css_class: "flair-discussion"
                },
                author: {
                  name: "business_excel_expert",
                  is_premium: true,
                  comment_karma: 12450,
                  link_karma: 3200
                },
                op_confirmed_solution: true,
                cross_posted: true
              }
            }
          ]
        }
      end

      it 'Reddit 형식 데이터를 정확히 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        post '/api/v1/pipedata', params: reddit_sample_data, headers: headers

        expect(response).to have_http_status(:ok)

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(2)

        # SUMIFS 관련 아이템 검증
        sumifs_item = KnowledgeItem.find_by("question LIKE ?", "%SUMIFS%")
        expect(sumifs_item).to be_present
        expect(sumifs_item.source).to eq("pipedata_reddit")
        expect(sumifs_item.difficulty).to eq(0) # easy
        expect(sumifs_item.quality_score).to eq(8.3)
        expect(sumifs_item.excel_functions).to include("SUMIF", "SUMIFS")
        expect(sumifs_item.tags).to include("beginner", "conditional-sum")

        # Reddit 메타데이터 검증
        expect(sumifs_item.metadata['reddit_post_id']).to eq("1a2b3c4d")
        expect(sumifs_item.metadata['subreddit']).to eq("excel")
        expect(sumifs_item.metadata['upvotes']).to eq(127)
        expect(sumifs_item.metadata['awards']).to be_an(Array)
        expect(sumifs_item.metadata['awards'].first['name']).to eq("Silver")
        expect(sumifs_item.metadata['flair']['text']).to eq("solved")
        expect(sumifs_item.metadata['op_confirmed_solution']).to be true

        # 재고 관리 아이템 검증
        inventory_item = KnowledgeItem.find_by("question LIKE ?", "%재고 관리%")
        expect(inventory_item).to be_present
        expect(inventory_item.difficulty).to eq(1) # medium
        expect(inventory_item.quality_score).to eq(9.0)
        expect(inventory_item.excel_functions).to include("IF", "CONDITIONAL_FORMATTING", "FILTER")
        expect(inventory_item.metadata['gilded']).to eq(1) # Gold award
        expect(inventory_item.metadata['edited']).to be true
      end
    end

    context '혼합 데이터 소스' do
      let(:mixed_source_data) do
        {
          data: [
            # Stack Overflow 스타일
            {
              question: "Excel에서 중복값을 찾아서 삭제하는 가장 효율적인 방법은 무엇인가요?",
              answer: "Excel에서 중복값을 처리하는 여러 방법이 있습니다:\n\n**1. 데이터 도구 사용 (권장)**\n- 데이터 선택 → 데이터 탭 → 중복 항목 제거\n- 간단하고 빠름\n\n**2. 고급 필터 사용**\n- 데이터 → 고급 필터\n- '중복 레코드 제외' 체크\n\n**3. 조건부 서식으로 중복값 강조**\n```excel\n=COUNTIF($A$1:A1,A1)>1\n```\n\n**4. 수식으로 중복 확인**\n```excel\n=IF(COUNTIF($A$1:A1,A1)>1,\"중복\",\"고유\")\n```",
              difficulty: "medium",
              quality_score: 8.9,
              source: "pipedata_stackoverflow",
              excel_functions: [ "COUNTIF", "REMOVE_DUPLICATES", "ADVANCED_FILTER" ],
              code_snippets: [
                "=COUNTIF($A$1:A1,A1)>1",
                "=IF(COUNTIF($A$1:A1,A1)>1,\"중복\",\"고유\")"
              ],
              tags: [ "excel", "duplicates", "data-cleaning", "countif" ],
              metadata: {
                stackoverflow_id: "98765432",
                question_score: 92,
                answer_score: 178,
                view_count: 45670,
                accepted_answer: true,
                created_date: "2023-09-10T11:20:00Z"
              }
            },
            # Reddit 스타일
            {
              question: "엑셀 차트에서 특정 데이터 포인트만 다른 색으로 강조하고 싶어요",
              answer: "차트에서 특정 포인트 강조하는 방법 알려드릴게요! 💡\n\n**방법 1: 개별 데이터 포인트 색상 변경**\n1. 차트에서 강조할 데이터 포인트 더블클릭\n2. 서식 → 채우기 색상 변경\n\n**방법 2: 보조 데이터 시리즈 사용 (더 고급)**\n1. 강조할 값만 별도 열에 입력 (나머지는 공백)\n2. 차트에 이 열도 추가\n3. 새 시리즈를 다른 색상으로 설정\n\n**방법 3: 조건부 서식 활용**\n- 원본 데이터에 조건부 서식 적용\n- 차트가 자동으로 색상 반영\n\n어떤 종류의 차트인지 알려주시면 더 구체적으로 도움드릴 수 있어요! 📊",
              difficulty: "easy",
              quality_score: 7.8,
              source: "pipedata_reddit",
              excel_functions: [ "CHART", "CONDITIONAL_FORMATTING" ],
              code_snippets: [],
              tags: [ "excel", "chart", "visualization", "formatting", "highlight" ],
              metadata: {
                reddit_post_id: "9i8j7k6l",
                subreddit: "excel",
                upvotes: 89,
                comment_count: 15,
                op_confirmed_solution: true,
                flair: { text: "solved", css_class: "flair-solved" }
              }
            },
            # 커스텀 소스
            {
              question: "Excel 매크로를 사용하지 않고 자동으로 날짜가 업데이트되는 보고서를 만들 수 있나요?",
              answer: "매크로 없이도 동적 보고서 만들기 가능해요! 여러 함수를 조합하면 됩니다.\n\n**1. 동적 날짜 함수들:**\n- `=TODAY()`: 오늘 날짜\n- `=NOW()`: 현재 날짜/시간\n- `=EOMONTH(TODAY(),0)`: 이번 달 마지막 날\n- `=WORKDAY(TODAY(),30)`: 30 영업일 후\n\n**2. 동적 범위 (OFFSET + COUNTA):**\n```excel\n=OFFSET(A1,0,0,COUNTA(A:A),1)\n```\n\n**3. 테이블 기능 활용:**\n- 데이터를 테이블로 변환 (Ctrl+T)\n- 자동으로 범위 확장\n\n**4. 피벗 테이블의 자동 새로 고침:**\n- 피벗 테이블 옵션에서 '파일을 열 때 새로 고침' 설정\n\n이런 조합으로 완전 자동화된 대시보드 구축 가능합니다!",
              difficulty: "hard",
              quality_score: 9.3,
              source: "pipedata_custom_tutorial",
              excel_functions: [ "TODAY", "NOW", "EOMONTH", "WORKDAY", "OFFSET", "COUNTA", "PIVOT_TABLE" ],
              code_snippets: [
                "=TODAY()",
                "=NOW()",
                "=EOMONTH(TODAY(),0)",
                "=WORKDAY(TODAY(),30)",
                "=OFFSET(A1,0,0,COUNTA(A:A),1)"
              ],
              tags: [ "excel", "automation", "dynamic", "reporting", "functions", "no-macro" ],
              metadata: {
                tutorial_id: "custom_001",
                author: "excel_automation_pro",
                source_type: "tutorial",
                language: "korean",
                difficulty_rating: "advanced",
                estimated_time_minutes: 45,
                prerequisites: [ "basic excel", "functions", "pivot tables" ]
              }
            }
          ]
        }
      end

      it '다양한 소스의 혼합 데이터를 올바르게 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        post '/api/v1/pipedata', params: mixed_source_data, headers: headers

        expect(response).to have_http_status(:ok)

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(3)
        expect(response_body['processed']).to eq(3)

        # 소스별 데이터 확인
        stackoverflow_item = KnowledgeItem.find_by(source: "pipedata_stackoverflow")
        reddit_item = KnowledgeItem.find_by(source: "pipedata_reddit")
        custom_item = KnowledgeItem.find_by(source: "pipedata_custom_tutorial")

        expect(stackoverflow_item).to be_present
        expect(reddit_item).to be_present
        expect(custom_item).to be_present

        # 난이도 분포 확인
        expect(stackoverflow_item.difficulty).to eq(1) # medium
        expect(reddit_item.difficulty).to eq(0) # easy
        expect(custom_item.difficulty).to eq(2) # hard

        # 품질 점수 확인
        expect(stackoverflow_item.quality_score).to eq(8.9)
        expect(reddit_item.quality_score).to eq(7.8)
        expect(custom_item.quality_score).to eq(9.3)

        # 메타데이터 구조 확인
        expect(stackoverflow_item.metadata.keys).to include('stackoverflow_id', 'view_count')
        expect(reddit_item.metadata.keys).to include('reddit_post_id', 'upvotes')
        expect(custom_item.metadata.keys).to include('tutorial_id', 'estimated_time_minutes')
      end
    end

    context '대용량 실제 데이터 시뮬레이션' do
      let(:realistic_large_dataset) do
        {
          data: Array.new(500) do |i|
            sources = [ 'pipedata_stackoverflow', 'pipedata_reddit', 'pipedata_custom' ]
            difficulties = [ 'easy', 'medium', 'hard', 'expert' ]
            functions = [
              [ 'VLOOKUP', 'HLOOKUP' ], [ 'INDEX', 'MATCH' ], [ 'SUMIF', 'SUMIFS' ],
              [ 'COUNTIF', 'COUNTIFS' ], [ 'IF', 'IFS' ], [ 'XLOOKUP', 'FILTER' ],
              [ 'PIVOT_TABLE' ], [ 'CONDITIONAL_FORMATTING' ], [ 'DATA_VALIDATION' ]
            ]

            source = sources[i % 3]
            difficulty = difficulties[i % 4]
            function_set = functions[i % functions.length]

            base_quality = case difficulty
            when 'easy' then 6.0 + rand(2.0)
            when 'medium' then 7.0 + rand(2.0)
            when 'hard' then 8.0 + rand(1.5)
            when 'expert' then 8.5 + rand(1.5)
            end

            {
              question: "대용량 테스트 #{i + 1}번: #{function_set.join('/')} 함수에 대한 질문입니다. #{difficulty} 수준의 질문으로, 실제 업무에서 자주 발생하는 상황을 다룹니다.",
              answer: "대용량 테스트 #{i + 1}번 답변: #{function_set.join('/')} 함수의 사용법과 관련된 상세한 설명입니다. 이 답변은 실제 사용자가 작성한 것처럼 충분한 길이와 내용을 포함하고 있으며, 실무에서 바로 적용할 수 있는 구체적인 예시와 팁을 제공합니다. #{difficulty} 수준에 맞는 설명 깊이를 유지하면서도 초보자도 이해할 수 있도록 구성되었습니다.",
              difficulty: difficulty,
              quality_score: base_quality.round(1),
              source: source,
              excel_functions: function_set,
              code_snippets: function_set.map { |f| "=#{f}(A1:A10)" },
              tags: [ "excel", function_set.first.downcase, difficulty, "realistic-test" ],
              metadata: case source
                        when 'pipedata_stackoverflow'
                         {
                           stackoverflow_id: (10000000 + i).to_s,
                           question_score: rand(100),
                           view_count: rand(10000),
                           accepted_answer: rand < 0.7
                         }
                        when 'pipedata_reddit'
                         {
                           reddit_post_id: "test_#{i}",
                           upvotes: rand(200),
                           comment_count: rand(50),
                           op_confirmed_solution: rand < 0.6
                         }
                        else
                         {
                           custom_id: "custom_#{i}",
                           estimated_time: rand(60),
                           tutorial_type: "realistic"
                         }
                        end
            }
          end
        }
      end

      it '500건의 현실적인 대용량 데이터를 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        start_time = Time.current

        post '/api/v1/pipedata', params: realistic_large_dataset, headers: headers

        processing_time = Time.current - start_time

        expect(response).to have_http_status(:ok)
        expect(processing_time).to be < 15.seconds # 500건은 15초 이내 처리

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(500)
        expect(response_body['processed']).to eq(500)
        expect(response_body['duplicates']).to eq(0)
        expect(response_body['errors']).to eq(0)

        # 데이터 분포 검증
        items = KnowledgeItem.last(500)

        # 소스 분포 확인 (대략 균등하게 분배되어야 함)
        source_distribution = items.group_by(&:source).transform_values(&:count)
        expect(source_distribution['pipedata_stackoverflow']).to be_between(160, 170)
        expect(source_distribution['pipedata_reddit']).to be_between(160, 170)
        expect(source_distribution['pipedata_custom']).to be_between(160, 170)

        # 난이도 분포 확인
        difficulty_distribution = items.group_by(&:difficulty).transform_values(&:count)
        expect(difficulty_distribution[0]).to be_between(120, 130) # easy
        expect(difficulty_distribution[1]).to be_between(120, 130) # medium
        expect(difficulty_distribution[2]).to be_between(120, 130) # hard
        expect(difficulty_distribution[3]).to be_between(120, 130) # expert

        # 품질 점수 분포 확인
        quality_scores = items.map(&:quality_score)
        average_quality = quality_scores.sum / quality_scores.length
        expect(average_quality).to be_between(7.0, 8.5)

        Rails.logger.info "500건 현실적 데이터 처리 완료 - 시간: #{processing_time.round(3)}초, 평균 품질: #{average_quality.round(2)}"
      end
    end
  end

  describe '데이터 품질 검증' do
    context '실제 사용 시나리오' do
      let(:quality_test_data) do
        {
          data: [
            # 고품질 데이터
            {
              question: "Excel에서 동적 배열 함수 FILTER와 UNIQUE를 조합하여 조건에 맞는 고유값만 추출하는 방법을 알려주세요.",
              answer: "동적 배열 함수는 Excel 365와 2021에서 사용할 수 있는 강력한 기능입니다.\n\n**FILTER + UNIQUE 조합 사용법:**\n\n```excel\n=UNIQUE(FILTER(A:A, B:B>100))\n```\n\n**단계별 설명:**\n1. `FILTER(A:A, B:B>100)`: B열이 100보다 큰 행의 A열 값들 필터링\n2. `UNIQUE()`: 필터링된 결과에서 중복값 제거\n\n**실용적 예시:**\n```excel\n// 판매량 1000 이상인 제품의 고유 카테고리\n=UNIQUE(FILTER(C:C, D:D>=1000))\n\n// 특정 날짜 이후 주문의 고유 고객\n=UNIQUE(FILTER(A:A, B:B>=DATE(2023,1,1)))\n```\n\n**오류 처리:**\n```excel\n=IFERROR(UNIQUE(FILTER(A:A, B:B>100)), \"조건에 맞는 데이터 없음\")\n```",
              difficulty: "expert",
              quality_score: 9.8,
              source: "pipedata_stackoverflow",
              excel_functions: [ "FILTER", "UNIQUE", "IFERROR", "DATE" ],
              code_snippets: [
                "=UNIQUE(FILTER(A:A, B:B>100))",
                "=UNIQUE(FILTER(C:C, D:D>=1000))",
                "=IFERROR(UNIQUE(FILTER(A:A, B:B>100)), \"조건에 맞는 데이터 없음\")"
              ],
              tags: [ "excel", "dynamic-arrays", "filter", "unique", "advanced", "excel365" ],
              metadata: {
                stackoverflow_id: "advanced_001",
                question_score: 145,
                view_count: 89230,
                accepted_answer: true,
                expert_verified: true
              }
            },
            # 중간 품질 데이터
            {
              question: "엑셀에서 IF 함수 여러 개 쓰는 방법이 있나요?",
              answer: "네, 여러 방법이 있어요!\n\n**중첩 IF:**\n=IF(조건1, 값1, IF(조건2, 값2, 값3))\n\n**IFS 함수 (Excel 2016+):**\n=IFS(조건1, 값1, 조건2, 값2, TRUE, 기본값)\n\n**예시:**\n=IFS(A1>=90, \"A\", A1>=80, \"B\", A1>=70, \"C\", TRUE, \"F\")\n\nIFS가 더 간단해요!",
              difficulty: "easy",
              quality_score: 6.8,
              source: "pipedata_reddit",
              excel_functions: [ "IF", "IFS" ],
              code_snippets: [
                "=IF(조건1, 값1, IF(조건2, 값2, 값3))",
                "=IFS(A1>=90, \"A\", A1>=80, \"B\", A1>=70, \"C\", TRUE, \"F\")"
              ],
              tags: [ "excel", "if", "ifs", "beginner" ],
              metadata: {
                reddit_post_id: "simple_if",
                upvotes: 45,
                comment_count: 12
              }
            },
            # 저품질 데이터 (하지만 유효)
            {
              question: "엑셀 합계 어떻게 하나요?",
              answer: "SUM 함수 쓰세요. =SUM(A1:A10) 이런 식으로요.",
              difficulty: "easy",
              quality_score: 4.2,
              source: "pipedata_forum",
              excel_functions: [ "SUM" ],
              code_snippets: [ "=SUM(A1:A10)" ],
              tags: [ "excel", "sum", "basic" ],
              metadata: {
                forum_id: "basic_001",
                helpful_count: 3
              }
            }
          ]
        }
      end

      it '다양한 품질의 데이터를 적절히 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        post '/api/v1/pipedata', params: quality_test_data, headers: headers

        expect(response).to have_http_status(:ok)

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(3)

        items = KnowledgeItem.last(3).sort_by(&:quality_score).reverse

        # 고품질 데이터 검증
        high_quality = items.first
        expect(high_quality.quality_score).to eq(9.8)
        expect(high_quality.difficulty).to eq(3) # expert
        expect(high_quality.excel_functions).to include("FILTER", "UNIQUE")
        expect(high_quality.question.length).to be > 50
        expect(high_quality.answer.length).to be > 200
        expect(high_quality.code_snippets.length).to be >= 3

        # 중품질 데이터 검증
        medium_quality = items.second
        expect(medium_quality.quality_score).to eq(6.8)
        expect(medium_quality.difficulty).to eq(0) # easy
        expect(medium_quality.excel_functions).to include("IF", "IFS")

        # 저품질 데이터 검증
        low_quality = items.last
        expect(low_quality.quality_score).to eq(4.2)
        expect(low_quality.answer.length).to be < 100 # 짧은 답변
        expect(low_quality.excel_functions).to eq([ "SUM" ])
      end
    end

    context '데이터 일관성 및 무결성' do
      it '모든 생성된 아이템이 올바른 구조를 가진다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 다양한 형태의 데이터로 테스트
        varied_data = {
          data: [
            {
              question: "구조 테스트 1: 기본 필드만 있는 데이터",
              answer: "구조 테스트 1 답변: 기본 필드만으로 구성된 데이터의 무결성을 확인합니다.",
              difficulty: "medium",
              quality_score: 7.0,
              source: "pipedata_structure_test"
            },
            {
              question: "구조 테스트 2: 모든 필드가 있는 완전한 데이터",
              answer: "구조 테스트 2 답변: 모든 선택적 필드를 포함한 완전한 데이터의 처리를 확인합니다.",
              difficulty: "hard",
              quality_score: 8.5,
              source: "pipedata_structure_test",
              excel_functions: [ "COMPLETE_TEST", "FULL_FIELD" ],
              code_snippets: [ "=COMPLETE_TEST()", "=FULL_FIELD(A1:A10)" ],
              tags: [ "complete", "structure", "test" ],
              metadata: {
                complete_test: true,
                all_fields_present: true,
                test_type: "structure_validation"
              }
            }
          ]
        }

        post '/api/v1/pipedata', params: varied_data, headers: headers

        expect(response).to have_http_status(:ok)

        created_items = KnowledgeItem.last(2)

        created_items.each do |item|
          # 필수 필드 검증
          expect(item.question).to be_present
          expect(item.answer).to be_present
          expect(item.source).to be_present
          expect(item.quality_score).to be_present
          expect(item.difficulty).to be_present

          # 데이터 타입 검증
          expect(item.quality_score).to be_a(Numeric)
          expect(item.difficulty).to be_a(Integer)
          expect(item.excel_functions).to be_an(Array)
          expect(item.code_snippets).to be_an(Array)
          expect(item.tags).to be_an(Array)
          expect(item.metadata).to be_a(Hash)
          expect(item.embedding).to be_an(Array)

          # 범위 검증
          expect(item.quality_score).to be_between(0.0, 10.0)
          expect(item.difficulty).to be_between(0, 3)
          expect(item.embedding.length).to eq(1536)

          # 기본값 검증
          expect(item.search_count).to eq(0)
          expect(item.use_count).to eq(0)
          expect(item.helpful_votes).to eq(0)
          expect(item.is_active).to be true
        end

        Rails.logger.info "데이터 구조 무결성 검증 완료 - 생성된 아이템: #{created_items.length}개"
      end
    end
  end
end
