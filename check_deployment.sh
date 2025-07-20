#!/bin/bash

# Railway 배포 상태 확인 스크립트

echo "🚀 Railway 배포 상태 확인"
echo "=========================="

# 도메인 설정 (배포 후 실제 도메인으로 변경)
DOMAIN=${1:-"your-project.railway.app"}

echo "📍 도메인: $DOMAIN"
echo ""

# 1. 헬스체크 엔드포인트 확인
echo "🏥 헬스체크 확인..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/up" 2>/dev/null)

if [ "$HEALTH_STATUS" = "200" ]; then
    echo "✅ 헬스체크 통과 (HTTP $HEALTH_STATUS)"
else
    echo "❌ 헬스체크 실패 (HTTP $HEALTH_STATUS)"
fi

# 2. 로그인 페이지 확인
echo ""
echo "🔐 로그인 페이지 확인..."
LOGIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/auth/login" 2>/dev/null)

if [ "$LOGIN_STATUS" = "200" ]; then
    echo "✅ 로그인 페이지 접근 가능 (HTTP $LOGIN_STATUS)"
else
    echo "❌ 로그인 페이지 접근 불가 (HTTP $LOGIN_STATUS)"
fi

# 3. 홈페이지 확인
echo ""
echo "🏠 홈페이지 확인..."
HOME_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/" 2>/dev/null)

if [ "$HOME_STATUS" = "200" ] || [ "$HOME_STATUS" = "302" ]; then
    echo "✅ 홈페이지 접근 가능 (HTTP $HOME_STATUS)"
else
    echo "❌ 홈페이지 접근 불가 (HTTP $HOME_STATUS)"
fi

# 4. API 엔드포인트 확인
echo ""
echo "📡 API 엔드포인트 확인..."
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/api/v1/files" 2>/dev/null)

if [ "$API_STATUS" = "200" ] || [ "$API_STATUS" = "401" ] || [ "$API_STATUS" = "403" ]; then
    echo "✅ API 엔드포인트 접근 가능 (HTTP $API_STATUS)"
else
    echo "❌ API 엔드포인트 접근 불가 (HTTP $API_STATUS)"
fi

# 5. 정적 파일 확인
echo ""
echo "📦 정적 파일 확인..."
CSS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/assets/application.css" 2>/dev/null)

if [ "$CSS_STATUS" = "200" ]; then
    echo "✅ CSS 파일 로드 가능 (HTTP $CSS_STATUS)"
else
    echo "⚠️  CSS 파일 로드 실패 (HTTP $CSS_STATUS) - 정상일 수 있음"
fi

echo ""
echo "=========================="
echo "📋 배포 확인 완료"

# 전체 상태 요약
if [ "$HEALTH_STATUS" = "200" ] && ([ "$HOME_STATUS" = "200" ] || [ "$HOME_STATUS" = "302" ]); then
    echo "🎉 배포 성공! 애플리케이션이 정상 작동 중입니다."
else
    echo "⚠️  배포에 문제가 있을 수 있습니다. Railway 로그를 확인해주세요."
fi

echo ""
echo "🔗 유용한 링크:"
echo "   - 애플리케이션: https://$DOMAIN"
echo "   - 로그인: https://$DOMAIN/auth/login"
echo "   - 관리자: https://$DOMAIN/admin"
echo "   - 헬스체크: https://$DOMAIN/up"