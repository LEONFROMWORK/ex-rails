# 🧮 ExcelApp FormulaEngine Service

**HyperFormula + ExcelJS 통합 분석 엔진**

ExcelJS와 HyperFormula 라이브러리를 통합하여 완전한 Excel 파일 처리 파이프라인을 제공하는 Node.js 마이크로서비스입니다.

## 🎯 주요 기능

### 📊 통합 분석 엔진
- **ExcelJS**: Excel 파일 직접 읽기/쓰기, 서식 처리
- **HyperFormula**: 수식 계산, 오류 검출, 의존성 분석
- **통합 워크플로우**: 파일 파싱 → 수식 분석 → 결과 생성

### 🔄 호환성 검증
- 데이터 타입 변환 검증
- 수식 표현 호환성 테스트
- 대량 데이터 처리 안정성
- 다중 시트 지원

### ⚡ 성능 최적화
- 메모리 효율적인 변환
- 배치 처리 지원
- 세션 관리 및 자동 정리
- 성능 측정 및 벤치마크

## 🏗️ 아키텍처

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   ExcelJS   │───▶│  Converter   │───▶│HyperFormula │
│             │    │              │    │             │
│ File I/O    │    │ Data Bridge  │    │ Calculation │
│ Formatting  │    │ Validation   │    │ Analysis    │
└─────────────┘    └──────────────┘    └─────────────┘
       ▲                   │                   │
       │                   ▼                   ▼
       └──────────── Report Generator ─────────┘
```

## 📚 라이브러리 비교

| 기능 | HyperFormula | ExcelJS | 통합 엔진 |
|------|-------------|---------|----------|
| **Excel 파일 파싱** | ❌ | ✅ | ✅ |
| **수식 계산** | ✅ (395개 함수) | ❌ | ✅ |
| **서식/스타일** | ❌ | ✅ | ✅ |
| **오류 검출** | ✅ | ❌ | ✅ |
| **의존성 분석** | ✅ | ❌ | ✅ |
| **순환 참조 탐지** | ✅ | ❌ | ✅ |
| **차트/이미지** | ❌ | ✅ | ✅ |
| **성능** | 매우 빠름 | 보통 | 빠름 |

## 🚀 설치 및 실행

### 1. 의존성 설치
```bash
npm install
```

### 2. 서비스 시작
```bash
# 개발 환경
npm run dev

# 프로덕션 환경
npm start

# 특정 포트 지정
PORT=3002 npm start
```

### 3. 상태 확인
```bash
curl http://localhost:3002/integrated/health
```

## 📖 API 문서

### 🔧 기본 엔드포인트

#### 헬스 체크
```bash
GET /integrated/health
```

#### 라이브러리 비교 정보
```bash
GET /integrated/comparison
```

### 📊 통합 분석 API

#### 1. 세션 생성
```bash
POST /integrated/sessions
Content-Type: application/json

{
  "options": {
    "hyperformula": {
      "licenseKey": "gpl-v3",
      "smartRounding": true
    }
  }
}
```

#### 2. Excel 파일 분석
```bash
POST /integrated/sessions/{sessionId}/analyze-file
Content-Type: multipart/form-data

FormData:
- excelFile: (Excel 파일)
- validateCompatibility: true
- compareWithOriginal: true
```

#### 3. 분석 보고서 다운로드
```bash
GET /integrated/sessions/{sessionId}/report?detailed=true
```

#### 4. 세션 상태 조회
```bash
GET /integrated/sessions/{sessionId}/status
```

#### 5. 세션 삭제
```bash
DELETE /integrated/sessions/{sessionId}
```

### 🧪 호환성 테스트

#### 데이터 변환 테스트
```bash
POST /integrated/convert/test
Content-Type: multipart/form-data

FormData:
- excelFile: (Excel 파일)
```

## 💻 사용 예제

### JavaScript 클라이언트 예제

```javascript
const axios = require('axios');
const FormData = require('form-data');
const fs = require('fs');

// 1. 세션 생성
const session = await axios.post('http://localhost:3002/integrated/sessions');
const sessionId = session.data.sessionId;

// 2. Excel 파일 분석
const formData = new FormData();
formData.append('excelFile', fs.createReadStream('sample.xlsx'));
formData.append('validateCompatibility', 'true');

const analysis = await axios.post(
  `http://localhost:3002/integrated/sessions/${sessionId}/analyze-file`,
  formData,
  { headers: formData.getHeaders() }
);

console.log('분석 결과:', analysis.data);

// 3. 보고서 다운로드
const report = await axios.get(
  `http://localhost:3002/integrated/sessions/${sessionId}/report`,
  { responseType: 'arraybuffer' }
);

fs.writeFileSync('analysis_report.xlsx', report.data);

// 4. 세션 정리
await axios.delete(`http://localhost:3002/integrated/sessions/${sessionId}`);
```

### cURL 예제

```bash
# 세션 생성
SESSION_ID=$(curl -s -X POST http://localhost:3002/integrated/sessions | jq -r .sessionId)

# 파일 분석
curl -X POST \
  -F "excelFile=@sample.xlsx" \
  -F "validateCompatibility=true" \
  http://localhost:3002/integrated/sessions/$SESSION_ID/analyze-file

# 보고서 다운로드
curl -o analysis_report.xlsx \
  "http://localhost:3002/integrated/sessions/$SESSION_ID/report?detailed=true"

# 세션 삭제
curl -X DELETE http://localhost:3002/integrated/sessions/$SESSION_ID
```

## 🧪 테스트 실행

### 통합 예제 실행
```bash
# 모든 예제 실행
node integration_examples.js

# 특정 예제 실행
node integration_examples.js 1  # 기본 Excel 파일 분석
node integration_examples.js 2  # 배치 파일 처리
node integration_examples.js 3  # 실시간 수식 검증
node integration_examples.js 4  # 호환성 검증
node integration_examples.js 5  # 성능 벤치마크
```

### 성능 테스트
```bash
node performance_test.js
```

### 호환성 검증
```bash
node compatibility_report.js
```

## 📊 성능 지표

### 처리 성능
- **소규모 파일** (10x10): ~10ms
- **중간 파일** (100x20): ~50ms  
- **대용량 파일** (1000x50): ~500ms

### 메모리 사용량
- **기본 서비스**: ~25MB
- **소규모 분석**: +5MB
- **대용량 분석**: +50MB

### 지원 형식
- **입력**: `.xlsx`, `.xls`, `.csv`
- **출력**: `.xlsx` (분석 보고서)
- **최대 파일 크기**: 50MB

## 🔍 호환성 검증 결과

### ✅ 높은 호환성 (90%+)
- 기본 데이터 타입 (숫자, 텍스트, 날짜)
- 표준 수식 함수 (SUM, AVERAGE, IF 등)
- 다중 시트 처리

### ⚠️ 제한적 호환성
- 복잡한 배열 수식
- Excel 전용 함수 일부
- 매크로/VBA 코드

### ❌ 미지원 기능
- 차트 수식 계산
- 피벗 테이블 동적 참조
- 외부 데이터 연결

## 🎯 사용 시나리오

### 1. Excel 파일 검증 서비스
```javascript
// 업로드된 Excel 파일의 수식 오류 검증
const validation = await analyzeExcelFile(buffer, {
  validateCompatibility: true,
  compareWithOriginal: true
});
```

### 2. 배치 파일 처리
```javascript
// 대량의 Excel 파일 일괄 분석
for (const file of excelFiles) {
  const result = await processExcelFile(file);
  generateReport(result);
}
```

### 3. 실시간 수식 검증
```javascript
// 사용자 입력 수식의 실시간 검증
const isValid = await validateFormula('=SUM(A1:A10)');
```

## 🛠️ 커스터마이제이션

### HyperFormula 설정
```javascript
const customConfig = {
  licenseKey: 'gpl-v3',
  useColumnIndex: true,
  smartRounding: true,
  numberEpsilon: 1e-10,
  dateFormats: ['MM/DD/YYYY', 'DD/MM/YYYY'],
  timeFormats: ['hh:mm', 'hh:mm:ss.sss']
};
```

### ExcelJS 옵션
```javascript
const excelOptions = {
  includeDetailedAnalysis: true,
  preserveFormatting: true,
  generateCharts: false
};
```

## 📈 모니터링

### 로그 확인
```bash
tail -f service.log
```

### 메트릭 수집
- 세션 수: `/integrated/health`
- 메모리 사용량: `process.memoryUsage()`
- 처리 시간: 각 API 응답에 포함

## 🔧 운영 가이드

### 환경 변수
```bash
PORT=3002                    # 서비스 포트
RAILS_HOST=http://localhost:3000  # Rails 앱 URL
NODE_ENV=production         # 환경 설정
```

### 프로덕션 배포
```bash
# PM2 사용
pm2 start index.js --name formula-engine

# Docker 사용
docker build -t formula-engine .
docker run -p 3002:3002 formula-engine
```

### 로드 밸런싱
- 세션 기반 sticky routing 권장
- Redis를 통한 세션 공유 가능
- 수평 확장 지원

## 🐛 문제 해결

### 일반적인 문제

#### 1. 포트 충돌
```bash
Error: listen EADDRINUSE: address already in use :::3002
```
**해결책**: 다른 포트 사용 `PORT=3003 npm start`

#### 2. 메모리 부족
```bash
FATAL ERROR: Ineffective mark-compacts near heap limit
```
**해결책**: Node.js 힙 크기 증가 `node --max-old-space-size=4096 index.js`

#### 3. 파일 형식 오류
```bash
지원하지 않는 파일 형식입니다
```
**해결책**: Excel 파일(.xlsx, .xls) 또는 CSV 파일만 업로드

### 성능 최적화

#### 대용량 파일 처리
```javascript
// 청크 단위 처리
const chunkSize = 1000;
for (let i = 0; i < data.length; i += chunkSize) {
  const chunk = data.slice(i, i + chunkSize);
  await processChunk(chunk);
}
```

#### 메모리 관리
```javascript
// 명시적 가비지 컬렉션
if (global.gc) {
  global.gc();
}
```

## 📝 변경 로그

### v2.0.0 (2025-07-19)
- ✨ ExcelJS + HyperFormula 통합 엔진 추가
- 🔄 호환성 검증 시스템 구현
- 📊 성능 벤치마크 도구 추가
- 📈 분석 보고서 생성 기능
- 🧪 통합 예제 및 테스트 스위트

### v1.0.0 (2025-07-16)
- 🎉 초기 HyperFormula 기반 서비스 출시
- 🧮 기본 수식 분석 기능
- 📡 REST API 제공

## 🤝 기여하기

1. Fork 프로젝트
2. Feature 브랜치 생성 (`git checkout -b feature/amazing-feature`)
3. 변경사항 커밋 (`git commit -m 'Add amazing feature'`)
4. 브랜치 푸시 (`git push origin feature/amazing-feature`)
5. Pull Request 생성

## 📄 라이선스

MIT License - 자세한 내용은 [LICENSE](LICENSE) 파일 참조

## 🔗 관련 링크

- [HyperFormula 공식 문서](https://hyperformula.handsontable.com/)
- [ExcelJS GitHub](https://github.com/exceljs/exceljs)
- [ExcelApp-Rails 메인 프로젝트](../README.md)

## 👥 개발팀

- **ExcelApp Team** - *초기 개발* - [GitHub](https://github.com/excelapp-team)

---

**🎯 ExcelApp FormulaEngine** - Excel 파일 처리의 새로운 표준