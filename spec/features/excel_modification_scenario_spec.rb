# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Excel Modification Scenario', type: :feature, js: true do
  let(:user) { create(:user, credits: 1000) }
  let(:excel_file) { create(:excel_file, user: user) }

  before do
    # Login the user using session-based auth
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:user_signed_in?).and_return(true)

    # Mock system services
    allow(User).to receive(:system_user).and_return(user)

    # Mock FormulaEngineClient
    formula_engine = instance_double('FormulaEngineClient')
    allow(FormulaEngineClient).to receive(:instance).and_return(formula_engine)
    allow(FormulaEngineClient).to receive(:validate_formula).and_return(
      Common::Result.success(valid: true, errors: [])
    )

    # Mock multimodal service
    multimodal_service = instance_double('AiIntegration::Services::MultimodalCoordinatorService')
    allow(AiIntegration::Services::MultimodalCoordinatorService).to receive(:new).and_return(multimodal_service)

    # Mock successful AI analysis
    allow(multimodal_service).to receive(:analyze_image).and_return(
      Common::Result.success({
        formula: '=SUM(A1:A10)',
        explanation: '요청하신 합계 공식입니다',
        confidence: 0.95,
        modifications: [
          {
            'type' => 'formula',
            'cell' => 'B1',
            'value' => '=SUM(A1:A10)',
            'description' => 'A1부터 A10까지의 합계'
          }
        ]
      })
    )

    # Mock Excel file operations
    allow_any_instance_of(ExcelModification::Services::ExcelModificationService).to receive(:apply_modifications).and_return(
      Common::Result.success({
        modified_file_path: Rails.root.join('tmp', 'modified_test.xlsx'),
        modifications_count: 1
      })
    )

    # Mock file upload
    modified_file = create(:excel_file, user: user, original_name: 'modified_test.xlsx')
    allow_any_instance_of(ExcelModification::Services::ExcelModificationService).to receive(:save_modified_file).and_return(
      Common::Result.success(modified_file)
    )
  end

  describe '시나리오: 사용자가 Excel 파일의 일부분을 수정 요청' do
    scenario '전체 플로우 테스트' do
      # 1. Excel 파일 상세 페이지 방문
      visit excel_file_path(excel_file)

      # 파일 정보가 표시되는지 확인
      expect(page).to have_content(excel_file.original_name)
      expect(page).to have_content('AI 기반 Excel 수정')

      # 2. 수정 섹션이 표시되는지 확인
      within('.modification-section') do
        expect(page).to have_css('.screenshot-upload-area')
        expect(page).to have_field('modification_request')
        expect(page).to have_button('Excel 수정하기')
      end

      # 3. 스크린샷 업로드 (드래그 앤 드롭 시뮬레이션)
      screenshot_file = File.open(Rails.root.join('spec', 'fixtures', 'screenshot.png'))
      attach_file('screenshot-input', screenshot_file.path, visible: false)

      # 스크린샷 미리보기가 표시되는지 확인
      expect(page).to have_css('.screenshot-preview img')

      # 4. 수정 요청 입력
      fill_in 'modification_request', with: 'A1부터 A10까지 합계를 구하는 공식을 B1에 넣어주세요'

      # 5. 수정 요청 전송
      click_button 'Excel 수정하기'

      # 로딩 상태 확인
      expect(page).to have_css('.loading-state', text: '처리 중')

      # 6. 성공 응답 확인
      expect(page).to have_css('.success-message', wait: 5)
      expect(page).to have_content('Excel 파일이 성공적으로 수정되었습니다')

      # 7. 수정 내역 표시 확인
      within('.modifications-summary') do
        expect(page).to have_content('적용된 수정사항')
        expect(page).to have_content('B1: =SUM(A1:A10)')
        expect(page).to have_content('A1부터 A10까지의 합계')
      end

      # 8. 다운로드 버튼 확인
      expect(page).to have_link('수정된 파일 다운로드', href: /download/)

      # 9. 크레딧 차감 확인
      expect(page).to have_content('사용된 크레딧: 50')

      # 사용자 크레딧이 차감되었는지 확인
      user.reload
      expect(user.credits).to eq(950)
    end

    scenario '스크린샷 없이 요청 시 오류' do
      visit excel_file_path(excel_file)

      # 스크린샷 없이 요청
      fill_in 'modification_request', with: '수정 요청'
      click_button 'Excel 수정하기'

      # 오류 메시지 확인
      expect(page).to have_css('.error-message')
      expect(page).to have_content('스크린샷을 업로드해주세요')
    end

    scenario '요청 내용 없이 전송 시 오류' do
      visit excel_file_path(excel_file)

      # 스크린샷만 업로드
      screenshot_file = File.open(Rails.root.join('spec', 'fixtures', 'screenshot.png'))
      attach_file('screenshot-input', screenshot_file.path, visible: false)

      # 요청 없이 전송
      click_button 'Excel 수정하기'

      # 오류 메시지 확인
      expect(page).to have_css('.error-message')
      expect(page).to have_content('수정 요청을 입력해주세요')
    end

    scenario '크레딧 부족 시 오류' do
      # 크레딧을 10으로 설정
      user.update!(credits: 10)

      visit excel_file_path(excel_file)

      # 정상적인 요청
      screenshot_file = File.open(Rails.root.join('spec', 'fixtures', 'screenshot.png'))
      attach_file('screenshot-input', screenshot_file.path, visible: false)
      fill_in 'modification_request', with: '수정 요청'
      click_button 'Excel 수정하기'

      # 크레딧 부족 오류 확인
      expect(page).to have_css('.error-message')
      expect(page).to have_content('크레딧이 부족합니다')
      expect(page).to have_content('필요 크레딧: 50')
      expect(page).to have_content('보유 크레딧: 10')
    end
  end

  describe 'UI/UX 사용성 검증' do
    scenario '드래그 앤 드롭으로 스크린샷 업로드' do
      visit excel_file_path(excel_file)

      # 드래그 앤 드롭 영역 확인
      drop_area = find('.screenshot-upload-area')
      expect(drop_area).to have_content('스크린샷을 드래그하여 놓거나 클릭하여 선택')

      # 드래그 오버 시 시각적 피드백
      drop_area.hover
      expect(drop_area[:class]).to include('drag-over')
    end

    scenario '클립보드에서 이미지 붙여넣기' do
      visit excel_file_path(excel_file)

      # Ctrl+V 키보드 이벤트 시뮬레이션
      find('body').send_keys [ :control, 'v' ]

      # 붙여넣기 안내 메시지 확인
      expect(page).to have_content('클립보드에서 이미지를 붙여넣을 수 있습니다')
    end

    scenario '수정 요청 입력 시 실시간 문자 수 표시' do
      visit excel_file_path(excel_file)

      # 텍스트 입력
      request_field = find('#modification_request')
      request_field.fill_in with: '이것은 테스트 요청입니다'

      # 문자 수 표시 확인
      expect(page).to have_content('12 / 500')
    end

    scenario '모바일 반응형 디자인' do
      # 모바일 뷰포트 설정
      page.driver.browser.manage.window.resize_to(375, 667)

      visit excel_file_path(excel_file)

      # 모바일에서도 모든 요소가 표시되는지 확인
      expect(page).to have_css('.modification-section')
      expect(page).to have_button('Excel 수정하기')

      # 버튼이 전체 너비로 표시되는지 확인
      button = find_button('Excel 수정하기')
      expect(button[:class]).to include('w-full')
    end
  end

  describe '접근성 검증' do
    scenario '키보드 네비게이션' do
      visit excel_file_path(excel_file)

      # Tab 키로 요소 간 이동
      find('body').send_keys :tab
      expect(page.evaluate_script('document.activeElement.className')).to include('screenshot-upload')

      find('body').send_keys :tab
      expect(page.evaluate_script('document.activeElement.id')).to eq('modification_request')

      find('body').send_keys :tab
      expect(page.evaluate_script('document.activeElement.textContent')).to include('Excel 수정하기')
    end

    scenario 'ARIA 레이블 확인' do
      visit excel_file_path(excel_file)

      # ARIA 속성 확인
      upload_area = find('.screenshot-upload-area')
      expect(upload_area['aria-label']).to eq('스크린샷 업로드 영역')

      request_field = find('#modification_request')
      expect(request_field['aria-label']).to eq('수정 요청 내용')
    end
  end
end
