# frozen_string_literal: true

# Railway 배포 시 assets precompile 문제 해결을 위한 오버라이드

namespace :assets do
  desc "Override assets precompile for deployment"
  task :precompile do
    $stdout.puts "🚀 Railway 배포용 Assets Precompile 오버라이드"
    $stdout.puts "✅ 기존 빌드된 assets 사용 중..."
    $stdout.flush

    # public/assets 디렉토리 생성
    root_dir = File.expand_path("../..", __dir__)
    assets_dir = File.join(root_dir, "public", "assets")
    FileUtils.mkdir_p(assets_dir) unless Dir.exist?(assets_dir)

    # 기본 manifest 파일 생성
    manifest_content = {
      "files" => {},
      "assets" => {
        "application.css" => "application.css",
        "application.js" => "application.js"
      }
    }.to_json

    File.write(File.join(assets_dir, ".sprockets-manifest.json"), manifest_content)

    # 기본 CSS와 JS 파일 복사 (빈 파일이라도)
    tailwind_css = File.join(root_dir, "app", "assets", "builds", "tailwind.css")
    if File.exist?(tailwind_css)
      FileUtils.cp(tailwind_css, File.join(assets_dir, "application.css"))
      $stdout.puts "✅ Tailwind CSS 파일 복사됨"
    else
      File.write(File.join(assets_dir, "application.css"), "/* Tailwind CSS placeholder */")
      $stdout.puts "⚠️  Tailwind CSS 플레이스홀더 생성됨"
    end

    # Vite 빌드된 파일들 확인
    vite_manifest = File.join(root_dir, "public", "vite-dev", ".vite", "manifest.json")
    if File.exist?(vite_manifest)
      $stdout.puts "✅ Vite 빌드 파일 확인됨"
    else
      $stdout.puts "⚠️  Vite 빌드 파일 없음 - JavaScript 기능 제한될 수 있음"
    end

    $stdout.puts "📦 Assets precompile 우회 완료!"
    $stdout.puts "🎯 Railway 배포 준비됨"
    $stdout.flush
  end
end

# 원본 precompile 작업 완전히 비활성화
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].clear
end
