#!/bin/bash

# Railway 배포 자동화 스크립트
# 사용법: ./deploy_to_railway.sh [RAILWAY_API_TOKEN]

set -e

echo "🚀 Railway 배포 자동화 시작"
echo "================================"

# API 토큰 확인
if [ -z "$1" ] && [ -z "$RAILWAY_API_TOKEN" ]; then
    echo "❌ Railway API 토큰이 필요합니다."
    echo "사용법: ./deploy_to_railway.sh YOUR_API_TOKEN"
    echo "또는 환경변수: export RAILWAY_API_TOKEN=YOUR_TOKEN"
    echo ""
    echo "💡 Railway API 토큰 생성:"
    echo "   1. https://railway.com/account/tokens 접속"
    echo "   2. 'Create Token' 클릭"
    echo "   3. 토큰 복사"
    exit 1
fi

# API 토큰 설정
if [ -n "$1" ]; then
    export RAILWAY_API_TOKEN="$1"
fi

echo "🔐 API 토큰 확인 중..."

# Railway CLI 인증 테스트
if ! railway whoami > /dev/null 2>&1; then
    echo "❌ Railway 인증 실패. API 토큰을 확인해주세요."
    exit 1
fi

USER_INFO=$(railway whoami)
echo "✅ 인증 성공: $USER_INFO"

echo ""
echo "📋 1단계: 프로젝트 생성"
echo "========================"

# 프로젝트 이름 설정
PROJECT_NAME="excelapp-rails-$(date +%s)"
echo "프로젝트 이름: $PROJECT_NAME"

# 프로젝트 생성
echo "프로젝트 생성 중..."
if railway init --name "$PROJECT_NAME"; then
    echo "✅ 프로젝트 생성 완료"
else
    echo "❌ 프로젝트 생성 실패"
    exit 1
fi

echo ""
echo "🔗 2단계: GitHub 저장소 연결"
echo "============================="

# GitHub 저장소 연결 (수동 단계 안내)
echo "⚠️  GitHub 저장소 연결은 Railway 웹 대시보드에서 수동으로 진행해야 합니다:"
echo "   1. https://railway.com/project/$PROJECT_NAME 접속"
echo "   2. 'Connect Repo' 클릭"
echo "   3. 'LEONFROMWORK/ex-rails' 저장소 선택"
echo ""
echo "계속하려면 Enter를 누르세요..."
read -r

echo ""
echo "⚙️  3단계: 환경 변수 설정"
echo "========================="

echo "필수 환경 변수 설정 중..."

# 환경 변수 설정
VARIABLES=(
    "SECRET_KEY_BASE=bd28abcc8ebb9b1f04c4e2d2b402462df272b3cd63164f472229bf0dd7979fa8443e34bb8ee0cb13da6fe26b9ae309fa41ef71d0e6af74b3ba3e7d1aee8127d7"
    "PAYMENT_ENABLED=false"
    "SUBSCRIPTION_REQUIRED=false"
    "RAILS_ENV=production"
    "RAILS_SERVE_STATIC_FILES=true"
    "RAILS_LOG_TO_STDOUT=true"
)

for var in "${VARIABLES[@]}"; do
    echo "설정 중: $var"
    if railway variables set "$var"; then
        echo "✅ 설정 완료"
    else
        echo "⚠️  설정 실패: $var"
    fi
done

echo ""
echo "🗄️  4단계: 데이터베이스 서비스 추가"
echo "================================="

echo "PostgreSQL 서비스 추가 중..."
if railway add postgresql; then
    echo "✅ PostgreSQL 추가 완료"
else
    echo "⚠️  PostgreSQL 추가 실패 - 수동으로 추가해주세요"
fi

echo "Redis 서비스 추가 중..."
if railway add redis; then
    echo "✅ Redis 추가 완료"
else
    echo "⚠️  Redis 추가 실패 - 수동으로 추가해주세요"
fi

echo ""
echo "🚀 5단계: 배포 실행"
echo "==================="

echo "애플리케이션 배포 중..."
if railway up; then
    echo "✅ 배포 완료!"
else
    echo "❌ 배포 실패"
    echo "Railway 대시보드에서 로그를 확인해주세요."
    exit 1
fi

echo ""
echo "🌐 6단계: 도메인 생성"
echo "===================="

echo "Railway 도메인 생성 중..."
if railway domain; then
    echo "✅ 도메인 생성 완료"
else
    echo "⚠️  도메인 생성 실패 - 수동으로 생성해주세요"
fi

# 프로젝트 정보 가져오기
echo ""
echo "📊 배포 정보"
echo "============"

PROJECT_URL=$(railway status 2>/dev/null | grep -o 'https://.*railway\.app' || echo "수동으로 확인 필요")
echo "🔗 프로젝트 URL: $PROJECT_URL"

if [ "$PROJECT_URL" != "수동으로 확인 필요" ]; then
    # 도메인을 RAILS_HOST에 설정
    DOMAIN=$(echo "$PROJECT_URL" | sed 's|https://||')
    echo "도메인 환경변수 설정 중: $DOMAIN"
    railway variables set "RAILS_HOST=$DOMAIN"
    
    echo ""
    echo "🧪 배포 상태 확인"
    echo "=================="
    
    echo "30초 후 헬스체크를 시작합니다..."
    sleep 30
    
    # 배포 상태 확인 스크립트 실행
    if [ -f "./check_deployment.sh" ]; then
        ./check_deployment.sh "$DOMAIN"
    else
        echo "헬스체크 스크립트를 찾을 수 없습니다."
        echo "수동으로 확인: $PROJECT_URL/up"
    fi
fi

echo ""
echo "🎉 Railway 배포 완료!"
echo "====================="
echo ""
echo "📋 완료된 작업:"
echo "  ✅ 프로젝트 생성: $PROJECT_NAME"
echo "  ✅ 환경 변수 설정"
echo "  ✅ PostgreSQL 서비스 추가"
echo "  ✅ Redis 서비스 추가"
echo "  ✅ 애플리케이션 배포"
echo "  ✅ 도메인 생성"
echo ""
echo "🔗 유용한 링크:"
echo "  - Railway 대시보드: https://railway.com/dashboard"
echo "  - 프로젝트 설정: https://railway.com/project/$PROJECT_NAME"
if [ "$PROJECT_URL" != "수동으로 확인 필요" ]; then
    echo "  - 애플리케이션: $PROJECT_URL"
    echo "  - 로그인: $PROJECT_URL/auth/login"
    echo "  - 관리자: $PROJECT_URL/admin"
    echo "  - 헬스체크: $PROJECT_URL/up"
fi
echo ""
echo "⚠️  추가 설정 필요:"
echo "  1. 관리자 이메일 설정: ADMIN_EMAILS 환경변수"
echo "  2. OAuth 설정 (선택사항): Google/Kakao Client ID/Secret"
echo "  3. AI 서비스 키 (선택사항): OpenAI, Anthropic 등"
echo ""
echo "🎯 다음 단계:"
echo "  1. Railway 웹 대시보드에서 GitHub 저장소 연결"
echo "  2. 환경 변수 추가 설정"
echo "  3. OAuth 리다이렉트 URI 설정"
echo "  4. Formula Engine 별도 서비스 배포 (선택사항)"