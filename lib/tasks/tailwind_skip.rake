# frozen_string_literal: true

# 배포 중 Tailwind CSS 빌드 오류 회피를 위한 임시 작업
# UTF-8 인코딩 문제로 인한 Tailwind 빌드 실패 시 사용

# Tailwind 빌드 작업을 빈 작업으로 오버라이드
Rake::Task["tailwindcss:build"].clear if Rake::Task.task_defined?("tailwindcss:build")

namespace :tailwindcss do
  desc "Skip Tailwind CSS build for deployment (temporary fix)"
  task :build do
    puts "⚠️  Tailwind CSS 빌드 건너뛰기 (UTF-8 인코딩 문제로 인해)"
    puts "✅ 기존 빌드된 CSS 파일 사용: app/assets/builds/tailwind.css"
  end
end

# Assets precompile 시 Tailwind 빌드를 건너뛰도록 설정
Rake::Task["assets:precompile"].enhance do
  puts "📦 Assets precompile 완료 (Tailwind CSS 빌드 제외)"
end
