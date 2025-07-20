# frozen_string_literal: true

namespace :quality do
  desc "전체 품질 검증 실행"
  task all: [ :lint, :security, :performance, :accessibility ]

  desc "Ruby 및 JavaScript 코드 린팅"
  task lint: :environment do
    puts "🔍 Ruby 코드 린팅 실행 중..."
    system("bundle exec rubocop") || exit(1)

    puts "🔍 JavaScript 코드 린팅 실행 중..."
    system("npm run lint:js") || exit(1)

    puts "✅ 린팅 완료"
  end

  desc "보안 검증 실행"
  task security: :environment do
    puts "🔒 보안 검증 실행 중..."

    # Brakeman 보안 검사 (설치된 경우)
    if system("which brakeman > /dev/null 2>&1")
      system("brakeman -q --no-pager") || exit(1)
    else
      puts "⚠️  Brakeman이 설치되지 않음. gem install brakeman으로 설치하세요."
    end

    # NPM 취약점 검사
    puts "📦 NPM 패키지 보안 검사 중..."
    system("npm audit --audit-level moderate") || exit(1)

    puts "✅ 보안 검증 완료"
  end

  desc "성능 분석"
  task performance: :environment do
    puts "⚡ 성능 분석 실행 중..."

    # CSS 크기 확인
    css_file = Rails.root.join("app/assets/builds/tailwind.css")
    if css_file.exist?
      size_kb = File.size(css_file) / 1024
      puts "📊 CSS 번들 크기: #{size_kb}KB"

      if size_kb > 500
        puts "⚠️  CSS 파일이 500KB를 초과합니다. 최적화를 고려해주세요."
      end
    end

    # 이미지 크기 확인
    image_dir = Rails.root.join("app/assets/images")
    if image_dir.exist?
      large_images = []
      Dir.glob(image_dir.join("**/*")).each do |file|
        next unless File.file?(file)
        next unless %w[.jpg .jpeg .png .gif .webp].include?(File.extname(file).downcase)

        size_kb = File.size(file) / 1024
        large_images << { file: file, size: size_kb } if size_kb > 1000
      end

      if large_images.any?
        puts "⚠️  1MB 이상의 큰 이미지들:"
        large_images.each do |img|
          puts "   #{File.basename(img[:file])}: #{img[:size]}KB"
        end
      end
    end

    puts "✅ 성능 분석 완료"
  end

  desc "접근성 가이드라인 확인"
  task accessibility: :environment do
    puts "♿ 접근성 검증 실행 중..."

    # HTML 템플릿에서 접근성 문제 확인
    html_files = Dir.glob(Rails.root.join("app/views/**/*.html.erb"))
    issues = []

    html_files.each do |file|
      content = File.read(file)

      # 기본적인 접근성 체크
      issues << "#{file}: img 태그에 alt 속성 누락" if content.match(/<img(?![^>]*alt=)/i)
      issues << "#{file}: form input에 label 누락 가능성" if content.match(/<input(?![^>]*(?:aria-label|aria-labelledby))/i) && !content.include?("<label")
      issues << "#{file}: button에 텍스트 누락 가능성" if content.match(/<button[^>]*>[\s]*<\/button>/i)
      issues << "#{file}: heading 순서 확인 필요" if content.scan(/<h([1-6])/i).flatten.map(&:to_i).each_cons(2).any? { |a, b| b - a > 1 }
    end

    if issues.any?
      puts "⚠️  접근성 개선이 필요한 부분들:"
      issues.each { |issue| puts "   #{issue}" }
    else
      puts "✅ 기본 접근성 검증 통과"
    end

    puts "✅ 접근성 검증 완료"
  end

  desc "테스트 커버리지 확인"
  task coverage: :environment do
    puts "📊 테스트 커버리지 분석 중..."

    # SimpleCov가 설치된 경우 커버리지 보고서 생성
    if defined?(SimpleCov)
      ENV["COVERAGE"] = "true"
      Rake::Task["spec"].invoke
    else
      puts "⚠️  SimpleCov가 설정되지 않음. 테스트 커버리지를 측정하려면 SimpleCov를 설정하세요."
    end

    puts "✅ 커버리지 분석 완료"
  end

  desc "코드 복잡도 분석"
  task complexity: :environment do
    puts "🧮 코드 복잡도 분석 중..."

    # Flog을 사용한 복잡도 분석 (설치된 경우)
    if system("which flog > /dev/null 2>&1")
      puts "실행: flog app/models app/controllers app/services"
      system("flog app/models app/controllers app/services app/features")
    else
      puts "⚠️  Flog가 설치되지 않음. gem install flog으로 설치하세요."
    end

    puts "✅ 복잡도 분석 완료"
  end

  desc "코드 품질 리포트 생성"
  task report: :environment do
    puts "📊 품질 리포트 생성 중..."

    report_file = Rails.root.join("tmp/quality_report.txt")
    File.open(report_file, "w") do |f|
      f.puts "ExcelApp-Rails 코드 품질 리포트"
      f.puts "생성일시: #{Time.current}"
      f.puts "=" * 50
      f.puts

      # Ruby 파일 통계
      ruby_files = Dir.glob(Rails.root.join("app/**/*.rb")).count
      f.puts "Ruby 파일 수: #{ruby_files}"

      # JavaScript 파일 통계
      js_files = Dir.glob(Rails.root.join("app/javascript/**/*.js")).count
      f.puts "JavaScript 파일 수: #{js_files}"

      # ERB 템플릿 통계
      erb_files = Dir.glob(Rails.root.join("app/views/**/*.erb")).count
      f.puts "ERB 템플릿 수: #{erb_files}"

      # 테스트 파일 통계
      spec_files = Dir.glob(Rails.root.join("spec/**/*_spec.rb")).count
      f.puts "테스트 파일 수: #{spec_files}"

      f.puts
      f.puts "자세한 분석을 위해 다음 명령어를 실행하세요:"
      f.puts "rake quality:all"
    end

    puts "📊 품질 리포트가 #{report_file}에 생성되었습니다."
  end

  desc "개발 환경 설정 확인"
  task setup_check: :environment do
    puts "🔧 개발 환경 설정 확인 중..."

    checks = {
      "Ruby 버전" => RUBY_VERSION >= "3.0",
      "Rails 버전" => Rails.version >= "7.0",
      "Node.js" => system("which node > /dev/null 2>&1"),
      "Yarn/NPM" => system("which npm > /dev/null 2>&1") || system("which yarn > /dev/null 2>&1"),
      "Redis" => system("redis-cli ping > /dev/null 2>&1"),
      "Database" => (ActiveRecord::Base.connection.active? rescue false)
    }

    checks.each do |check, result|
      status = result ? "✅" : "❌"
      puts "#{status} #{check}"
    end

    puts
    puts "✅ 환경 설정 확인 완료"
  end
end
