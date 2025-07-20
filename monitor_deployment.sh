#!/bin/bash

# Railway 배포 실시간 모니터링 스크립트
# 사용법: ./monitor_deployment.sh [domain]

set -e

echo "🔍 Railway 배포 실시간 모니터링"
echo "================================"

DOMAIN=${1:-""}
TIMEOUT=300  # 5분 타임아웃
INTERVAL=10  # 10초 간격 체크

if [ -z "$DOMAIN" ]; then
    echo "⚠️  도메인을 입력하지 않았습니다."
    echo "Railway 대시보드에서 도메인 생성 후 다시 실행해주세요."
    echo "사용법: ./monitor_deployment.sh your-app.railway.app"
    echo ""
    echo "🔗 도메인 확인 방법:"
    echo "   1. Railway 대시보드 접속"
    echo "   2. 프로젝트 > Settings > Networking"
    echo "   3. 생성된 도메인 복사"
    exit 1
fi

echo "📍 모니터링 대상: $DOMAIN"
echo "⏱️  타임아웃: ${TIMEOUT}초"
echo "🔄 체크 간격: ${INTERVAL}초"
echo ""

# 시작 시간 기록
START_TIME=$(date +%s)

echo "🚀 배포 상태 모니터링 시작..."
echo "================================"

DEPLOYMENT_READY=false
HEALTH_CHECK_PASSED=false
LOGIN_PAGE_READY=false
ADMIN_PAGE_READY=false

while [ $(($(date +%s) - START_TIME)) -lt $TIMEOUT ]; do
    CURRENT_TIME=$(date +"%H:%M:%S")
    echo "[$CURRENT_TIME] 상태 확인 중..."
    
    # 1. 기본 연결 확인
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
        if [ "$DEPLOYMENT_READY" = false ]; then
            echo "✅ [$CURRENT_TIME] 배포 완료! (HTTP $HTTP_STATUS)"
            DEPLOYMENT_READY=true
        fi
    else
        echo "⏳ [$CURRENT_TIME] 배포 진행 중... (HTTP $HTTP_STATUS)"
    fi
    
    # 2. 헬스체크 확인
    if [ "$DEPLOYMENT_READY" = true ]; then
        HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/up" 2>/dev/null || echo "000")
        
        if [ "$HEALTH_STATUS" = "200" ]; then
            if [ "$HEALTH_CHECK_PASSED" = false ]; then
                echo "✅ [$CURRENT_TIME] 헬스체크 통과!"
                HEALTH_CHECK_PASSED=true
            fi
        else
            echo "⏳ [$CURRENT_TIME] 헬스체크 대기 중... (HTTP $HEALTH_STATUS)"
        fi
    fi
    
    # 3. 로그인 페이지 확인
    if [ "$HEALTH_CHECK_PASSED" = true ]; then
        LOGIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/auth/login" 2>/dev/null || echo "000")
        
        if [ "$LOGIN_STATUS" = "200" ]; then
            if [ "$LOGIN_PAGE_READY" = false ]; then
                echo "✅ [$CURRENT_TIME] 로그인 페이지 준비 완료!"
                LOGIN_PAGE_READY=true
            fi
        else
            echo "⏳ [$CURRENT_TIME] 로그인 페이지 로딩 중... (HTTP $LOGIN_STATUS)"
        fi
    fi
    
    # 4. 관리자 페이지 확인 (접근 제한 확인)
    if [ "$LOGIN_PAGE_READY" = true ]; then
        ADMIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/admin" 2>/dev/null || echo "000")
        
        if [ "$ADMIN_STATUS" = "302" ] || [ "$ADMIN_STATUS" = "401" ] || [ "$ADMIN_STATUS" = "403" ]; then
            if [ "$ADMIN_PAGE_READY" = false ]; then
                echo "✅ [$CURRENT_TIME] 관리자 접근 제한 작동! (HTTP $ADMIN_STATUS)"
                ADMIN_PAGE_READY=true
            fi
        else
            echo "⏳ [$CURRENT_TIME] 관리자 페이지 설정 중... (HTTP $ADMIN_STATUS)"
        fi
    fi
    
    # 모든 체크 완료 시 종료
    if [ "$DEPLOYMENT_READY" = true ] && [ "$HEALTH_CHECK_PASSED" = true ] && [ "$LOGIN_PAGE_READY" = true ] && [ "$ADMIN_PAGE_READY" = true ]; then
        echo ""
        echo "🎉 배포 완료 및 모든 기능 정상 작동!"
        echo "=================================="
        break
    fi
    
    echo "   - 배포: $([ "$DEPLOYMENT_READY" = true ] && echo "✅" || echo "⏳")"
    echo "   - 헬스체크: $([ "$HEALTH_CHECK_PASSED" = true ] && echo "✅" || echo "⏳")"
    echo "   - 로그인: $([ "$LOGIN_PAGE_READY" = true ] && echo "✅" || echo "⏳")"
    echo "   - 관리자: $([ "$ADMIN_PAGE_READY" = true ] && echo "✅" || echo "⏳")"
    echo ""
    
    sleep $INTERVAL
done

# 최종 상태 보고
echo ""
echo "📊 최종 배포 상태 보고"
echo "====================="

ELAPSED_TIME=$(($(date +%s) - START_TIME))
echo "⏱️  소요 시간: ${ELAPSED_TIME}초"
echo ""

if [ "$DEPLOYMENT_READY" = true ] && [ "$HEALTH_CHECK_PASSED" = true ]; then
    echo "🎉 배포 성공!"
    echo ""
    echo "🔗 접속 링크:"
    echo "   - 애플리케이션: https://$DOMAIN"
    echo "   - 로그인: https://$DOMAIN/auth/login"
    echo "   - 관리자: https://$DOMAIN/admin"
    echo "   - 헬스체크: https://$DOMAIN/up"
    echo ""
    echo "📋 다음 단계:"
    echo "   1. 관리자 이메일 설정: ADMIN_EMAILS 환경변수"
    echo "   2. OAuth 설정 (선택): Google/Kakao Client ID/Secret"
    echo "   3. 기능 테스트: 파일 업로드 및 분석"
    
    # 최종 기능 테스트 실행
    echo ""
    echo "🧪 최종 기능 테스트 실행..."
    ./check_deployment.sh "$DOMAIN"
    
else
    echo "⚠️  배포에 문제가 있을 수 있습니다."
    echo ""
    echo "🔧 문제 해결:"
    echo "   1. Railway 대시보드 > Deployments > 로그 확인"
    echo "   2. 환경 변수 설정 재확인"
    echo "   3. 수동 재배포 시도"
    echo ""
    echo "📞 지원:"
    echo "   - Railway Discord: https://discord.gg/railway"
    echo "   - GitHub Issues: https://github.com/LEONFROMWORK/ex-rails/issues"
fi

echo ""
echo "🏁 모니터링 완료"