# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'UI Components Rendering', type: :feature, js: true do
  let(:user) { create(:user, credits: 100) }
  let!(:excel_file) { create(:excel_file, user: user, status: 'analyzed') }
  let!(:analysis) { create(:analysis, :with_formula_analysis, excel_file: excel_file, user: user) }

  before do
    login_as(user)
  end

  describe 'Excel File Show Page UI Components' do
    before do
      visit excel_file_path(excel_file)
    end

    describe 'File Information Header' do
      it 'displays file metadata correctly' do
        expect(page).to have_content(excel_file.original_name)
        expect(page).to have_content(number_to_human_size(excel_file.file_size))
        expect(page).to have_content(time_ago_in_words(excel_file.created_at))
        expect(page).to have_content(excel_file.status.humanize)
      end

      it 'shows file status with appropriate styling' do
        expect(page).to have_css('.status-analyzed')
        expect(page).to have_css('.fas.fa-circle')
      end

      it 'displays action buttons' do
        expect(page).to have_link('Download Original')
        expect(page).to have_button('Re-analyze') if excel_file.can_be_analyzed?
      end
    end

    describe 'Tab Navigation System' do
      it 'renders all tab buttons correctly' do
        expect(page).to have_css('[data-tab="analysis"]', text: 'Analysis Results')
        expect(page).to have_css('[data-tab="vba"]', text: 'VBA Analysis')
        expect(page).to have_css('[data-tab="formula"]', text: 'Formula Analysis')
        expect(page).to have_css('[data-tab="image"]', text: 'Image Analysis')
        expect(page).to have_css('[data-tab="history"]', text: 'History')
      end

      it 'activates first tab by default' do
        expect(page).to have_css('[data-tab="analysis"].active')
        expect(page).to have_css('#analysis-tab:not(.hidden)')
      end

      it 'switches tabs on click' do
        click_on 'Formula Analysis'

        expect(page).to have_css('[data-tab="formula"].active')
        expect(page).to have_css('#formula-tab:not(.hidden)')
        expect(page).to have_css('#analysis-tab.hidden')
      end

      it 'displays tab icons correctly' do
        expect(page).to have_css('.fas.fa-chart-line') # Analysis Results
        expect(page).to have_css('.fas.fa-code') # VBA Analysis
        expect(page).to have_css('.fas.fa-calculator') # Formula Analysis
        expect(page).to have_css('.fas.fa-image') # Image Analysis
        expect(page).to have_css('.fas.fa-history') # History
      end
    end

    describe 'Analysis Results Tab' do
      it 'displays analysis summary cards' do
        within('#analysis-tab') do
          expect(page).to have_content('Analysis Summary')
          expect(page).to have_content('Error Types')
          expect(page).to have_content('Processing Info')
        end
      end

      it 'shows analysis metrics' do
        within('#analysis-tab') do
          expect(page).to have_content('Errors Found')
          expect(page).to have_content('AI Tier')
          expect(page).to have_content('Confidence')
          expect(page).to have_content('Tokens Used')
        end
      end

      it 'displays AI analysis results' do
        within('#analysis-tab') do
          expect(page).to have_content('AI Analysis Results')
          expect(page).to have_content(analysis.ai_analysis)
        end
      end

      it 'shows detected errors if any' do
        if analysis.detected_errors.any?
          within('#analysis-tab') do
            expect(page).to have_content('Detected Errors')
            expect(page).to have_css('.border-red-500') # Error styling
          end
        end
      end
    end

    describe 'Formula Analysis Tab' do
      before do
        click_on 'Formula Analysis'
      end

      context 'when formula analysis exists' do
        it 'displays formula complexity card' do
          within('#formula-tab') do
            expect(page).to have_content('Formula Complexity')
            expect(page).to have_content('Complexity Score')
            expect(page).to have_css('[data-formula-analysis-target="complexityScore"]')
            expect(page).to have_css('[data-formula-analysis-target="complexityLevel"]')
          end
        end

        it 'shows formula statistics grid' do
          within('#formula-tab') do
            expect(page).to have_content('Total Formulas')
            expect(page).to have_content('Unique Functions')
            expect(page).to have_content('Circular Refs')
            expect(page).to have_css('.formula-stats-grid')
          end
        end

        it 'renders function usage chart' do
          within('#formula-tab') do
            expect(page).to have_content('Function Categories')
            expect(page).to have_css('canvas[data-formula-analysis-target="functionChart"]')
          end
        end

        it 'displays function usage table' do
          within('#formula-tab') do
            expect(page).to have_content('Most Used Functions')
            expect(page).to have_css('[data-formula-analysis-target="functionTable"]')
          end
        end

        it 'shows dependency analysis if available' do
          if analysis.formula_dependencies.present?
            within('#formula-tab') do
              expect(page).to have_content('Formula Dependencies')
              expect(page).to have_content('Dependencies Overview')
              expect(page).to have_css('canvas[data-formula-analysis-target="dependencyChart"]')
            end
          end
        end

        it 'displays circular references warning if any' do
          if analysis.has_circular_references?
            within('#formula-tab') do
              expect(page).to have_content('Circular References Detected')
              expect(page).to have_css('.border-red-200.bg-red-50')
            end
          end
        end

        it 'shows formula errors if any' do
          if analysis.formula_error_count > 0
            within('#formula-tab') do
              expect(page).to have_content('Formula Errors')
              expect(page).to have_css('[data-formula-analysis-target="errorsList"]')
            end
          end
        end

        it 'displays optimization suggestions if any' do
          if analysis.optimization_suggestion_count > 0
            within('#formula-tab') do
              expect(page).to have_content('Optimization Suggestions')
              expect(page).to have_css('[data-formula-analysis-target="optimizationList"]')
            end
          end
        end
      end

      context 'when no formula analysis exists' do
        let!(:analysis) { create(:analysis, excel_file: excel_file, user: user) }

        it 'shows empty state with analyze button' do
          within('#formula-tab') do
            expect(page).to have_content('No Formula Analysis Available')
            expect(page).to have_button('Analyze Formulas (5 tokens)')
          end
        end
      end
    end

    describe 'VBA Analysis Tab' do
      before do
        click_on 'VBA Analysis'
      end

      it 'displays VBA analysis interface' do
        within('#vba-tab') do
          expect(page).to have_content('VBA Code Analysis')
          expect(page).to have_button('Analyze VBA (10 tokens)')
        end
      end

      it 'shows VBA placeholder content' do
        within('#vba-tab') do
          expect(page).to have_content('Analyze VBA code for security issues')
          expect(page).to have_css('.fas.fa-code')
        end
      end
    end
  end

  describe 'Responsive Design' do
    it 'adapts to mobile viewport' do
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone SE size

      visit excel_file_path(excel_file)

      # Check if responsive classes are applied
      expect(page).to have_css('.grid-cols-1') # Should use single column on mobile
      expect(page).to have_css('.sm\\:grid-cols-2') # Should use 2 columns on small screens
    end

    it 'maintains functionality on tablet viewport' do
      page.driver.browser.manage.window.resize_to(768, 1024) # iPad size

      visit excel_file_path(excel_file)

      # Tabs should still work
      click_on 'Formula Analysis'
      expect(page).to have_css('[data-tab="formula"].active')
    end
  end

  describe 'Interactive Elements' do
    describe 'Button States' do
      it 'shows different button states correctly' do
        visit excel_file_path(excel_file)

        # Default button
        expect(page).to have_css('button:not([disabled])')

        # When clicked, button should show loading state
        click_on 'VBA Analysis'
        click_button 'Analyze VBA (10 tokens)'

        expect(page).to have_button('Analyzing...', disabled: true)
      end
    end

    describe 'Progress Indicators' do
      it 'displays progress bars when analysis is running' do
        excel_file.update!(status: 'processing')

        visit excel_file_path(excel_file)

        expect(page).to have_css('[data-progress-container]')
        expect(page).to have_css('.progress-bar')
      end
    end

    describe 'Loading States' do
      it 'shows loading components during async operations' do
        visit excel_file_path(excel_file)

        click_on 'Formula Analysis'
        click_button 'Analyze Formulas (5 tokens)'

        # Should show loading indicator
        expect(page).to have_css('.fas.fa-spinner.fa-spin')
      end
    end
  end

  describe 'Chart Rendering' do
    before do
      visit excel_file_path(excel_file)
      click_on 'Formula Analysis'
    end

    it 'initializes Chart.js charts correctly' do
      # Wait for charts to load
      sleep(1)

      # Check if canvas elements exist
      expect(page).to have_css('canvas[data-formula-analysis-target="functionChart"]')

      # Check if charts are initialized (Chart.js adds data attributes)
      expect(page).to have_css('canvas[style*="width"]')
    end

    it 'responds to data updates' do
      # Simulate data update
      page.execute_script(<<~JS)
        const controller = application.getControllerForElementAndIdentifier(
          document.querySelector('[data-controller="formula-analysis"]'),#{' '}
          'formula-analysis'
        );
        if (controller) {
          controller.updateCharts();
        }
      JS

      # Charts should still be visible
      expect(page).to have_css('canvas[data-formula-analysis-target="functionChart"]')
    end
  end

  describe 'Accessibility Features' do
    it 'includes proper ARIA attributes' do
      visit excel_file_path(excel_file)

      # Tab navigation should have proper roles
      expect(page).to have_css('[role="tablist"]')
      expect(page).to have_css('[role="tab"]')
      expect(page).to have_css('[role="tabpanel"]')
    end

    it 'supports keyboard navigation' do
      visit excel_file_path(excel_file)

      # Tab key should move focus
      find('[data-tab="analysis"]').send_keys(:tab)
      expect(page).to have_css('[data-tab="vba"]:focus')
    end

    it 'provides screen reader friendly content' do
      visit excel_file_path(excel_file)

      # Should have descriptive text for screen readers
      expect(page).to have_css('[aria-label]')
      expect(page).to have_css('[alt]') if page.has_css?('img')
    end
  end

  describe 'Error Display Components' do
    let!(:analysis_with_errors) do
      create(:analysis,
        excel_file: excel_file,
        user: user,
        detected_errors: [
          { 'type' => 'formula_error', 'message' => 'Invalid reference', 'location' => 'A1', 'formula' => '=INVALID()' },
          { 'type' => 'circular_reference', 'message' => 'Circular reference detected', 'location' => 'B2' }
        ]
      )
    end

    before do
      excel_file.analyses.destroy_all
      excel_file.analyses << analysis_with_errors
    end

    it 'displays error cards with proper styling' do
      visit excel_file_path(excel_file)

      expect(page).to have_content('Detected Errors (2)')
      expect(page).to have_css('.border-red-500, .text-red-800')
      expect(page).to have_content('Invalid reference')
      expect(page).to have_content('Circular reference detected')
    end

    it 'shows error locations and formulas' do
      visit excel_file_path(excel_file)

      expect(page).to have_content('A1')
      expect(page).to have_content('B2')
      expect(page).to have_content('=INVALID()')
    end
  end

  describe 'Theme Support' do
    it 'applies light theme correctly' do
      visit excel_file_path(excel_file)

      expect(page).to have_css('.bg-white, .text-gray-900')
    end

    it 'supports dark theme toggle' do
      # Simulate dark theme activation
      page.execute_script("document.documentElement.classList.add('dark')")

      visit excel_file_path(excel_file)

      # Dark theme classes should be applied
      expect(page).to have_css('.dark')
    end
  end

  private

  def login_as(user)
    visit '/auth/login'
    fill_in 'email', with: user.email
    fill_in 'password', with: 'password'
    click_button 'Sign In'
  end
end
