/** @type {import('tailwindcss').Config} */
const shadcnConfig = require('./config/shadcn.tailwind.js');

module.exports = {
  ...shadcnConfig,
  content: [
    './app/views/**/*.html.erb',
    './app/assets/stylesheets/**/*.css',
    './app/javascript/**/*.js',
    './app/javascript/**/*.vue',
    './app/javascript/**/*.ts',
    './app/components/**/*.{erb}',
    './app/views/**/*.{erb,haml,html,slim}',
    // Ruby 파일들을 제외하여 UTF-8 인코딩 문제 방지
    // './app/helpers/**/*.rb', 
    // './app/components/**/*.rb',
  ],
  theme: {
    ...shadcnConfig.theme,
    // 폰트 로딩 최적화
    fontFamily: {
      sans: ['Pretendard', '-apple-system', 'BlinkMacSystemFont', 'system-ui', 'Roboto', 'Helvetica Neue', 'Segoe UI', 'Apple SD Gothic Neo', 'Noto Sans KR', 'Malgun Gothic', 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol', 'sans-serif'],
      mono: ['JetBrains Mono', 'Fira Code', 'Monaco', 'Consolas', 'monospace'],
    },
    // 성능 최적화를 위한 애니메이션 제한
    transitionDuration: {
      DEFAULT: '150ms',
      75: '75ms',
      100: '100ms',
      150: '150ms',
      200: '200ms',
      300: '300ms',
      500: '500ms',
    }
  },
  corePlugins: {
    // 사용하지 않는 플러그인 비활성화
    float: false,
    clear: false,
    skew: false,
    sepia: false,
    saturate: false,
    hueRotate: false,
    brightness: false,
    contrast: false,
    grayscale: false,
    invert: false,
  },
  // 개발 환경에서 unused CSS 제거 활성화
  experimental: {
    optimizeUniversalDefaults: true,
  }
}