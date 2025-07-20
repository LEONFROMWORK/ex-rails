const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const multer = require('multer');
const { HyperFormula } = require('hyperformula');
const IntegratedEngine = require('./integrated_engine');
const ExcelConverter = require('./excel_converter');

console.log('🚀 ExcelApp FormulaEngine Service 시작');
console.log('=' * 50);

const app = express();
const PORT = process.env.PORT || 3001;

// 미들웨어 설정
app.use(helmet());
app.use(compression());
app.use(cors({
  origin: process.env.RAILS_HOST || 'http://localhost:3000',
  credentials: true
}));
app.use(morgan('combined'));
app.use(express.json({ limit: '10mb' }));

// HyperFormula 최적화 설정
const HF_CONFIG = {
  licenseKey: 'gpl-v3',
  
  // 성능 최적화 옵션
  useArrayArithmetic: true,      // 배열 연산 성능 향상
  matrixDetection: true,         // 대규모 행렬 연산 최적화
  matrixDetectionThreshold: 100, // 100개 이상 셀을 행렬로 처리
  
  // 캐싱 활성화
  useColumnIndex: true,          // 컬럼 인덱싱으로 조회 성능 향상
  smartRounding: true,           // 스마트 반올림 (주의: Excel과 약간 다를 수 있음)
  
  // 메모리 최적화
  undoLimit: 0,                  // Undo 비활성화로 메모리 절약
  
  // 계산 최적화
  evaluateNullToZero: false,     // NULL을 0으로 평가하지 않음 (Excel 호환)
  precisionRounding: 10,         // 소수점 10자리 반올림
  numberEpsilon: 1e-10,          // 수치 비교 임계값
  
  // 날짜/시간 형식
  dateFormats: ['MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD'],
  timeFormats: ['hh:mm', 'hh:mm:ss.sss']
};

// 메모리 내 세션 저장소 (프로덕션에서는 Redis 사용)
const sessions = new Map();
const integratedSessions = new Map();

// Multer 설정 (파일 업로드용)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 50 * 1024 * 1024, // 50MB 제한
  },
  fileFilter: (req, file, cb) => {
    const allowedTypes = [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', // .xlsx
      'application/vnd.ms-excel', // .xls
      'text/csv' // .csv
    ];
    
    if (allowedTypes.includes(file.mimetype) || file.originalname.match(/\.(xlsx|xls|csv)$/i)) {
      cb(null, true);
    } else {
      cb(new Error('지원하지 않는 파일 형식입니다. Excel 파일(.xlsx, .xls) 또는 CSV 파일만 업로드 가능합니다.'), false);
    }
  }
});

// FormulaEngine 클래스
class FormulaEngine {
  constructor(sessionId) {
    this.sessionId = sessionId;
    this.hyperFormula = null;
    this.sheets = new Map();
    this.lastActivity = Date.now();
  }

  // Excel 데이터로부터 HyperFormula 인스턴스 생성
  createFromExcelData(excelData) {
    try {
      if (Array.isArray(excelData) && excelData.length > 0) {
        // 2D 배열 형태의 데이터
        this.hyperFormula = HyperFormula.buildFromArray(excelData, HF_CONFIG);
      } else if (typeof excelData === 'object' && excelData.sheets) {
        // 다중 시트 데이터
        this.hyperFormula = HyperFormula.buildFromSheets(excelData.sheets, HF_CONFIG);
      } else {
        // 빈 워크북 생성
        this.hyperFormula = HyperFormula.buildEmpty(HF_CONFIG);
      }
      
      this.lastActivity = Date.now();
      return { success: true, message: 'FormulaEngine 생성 완료' };
    } catch (error) {
      return { success: false, error: error.message };
    }
  }

  // 수식 분석
  analyzeFormulas() {
    if (!this.hyperFormula) {
      return { success: false, error: 'HyperFormula 인스턴스가 없습니다.' };
    }

    try {
      const analysis = {
        sheets: [],
        totalFormulas: 0,
        formulaComplexity: { simple: 0, medium: 0, complex: 0 },
        functions: {},
        errors: [],
        dependencies: [],
        circularReferences: []
      };

      // 모든 시트 분석
      this.hyperFormula.getSheetNames().forEach(sheetName => {
        const sheetId = this.hyperFormula.getSheetId(sheetName);
        const sheetAnalysis = this.analyzeSheet(sheetId, sheetName);
        analysis.sheets.push(sheetAnalysis);
        
        // 전체 통계 업데이트
        analysis.totalFormulas += sheetAnalysis.formulaCount;
        Object.entries(sheetAnalysis.functions).forEach(([func, count]) => {
          analysis.functions[func] = (analysis.functions[func] || 0) + count;
        });
        
        analysis.errors.push(...sheetAnalysis.errors);
        analysis.dependencies.push(...sheetAnalysis.dependencies);
      });

      this.lastActivity = Date.now();
      return { success: true, data: analysis };
    } catch (error) {
      return { success: false, error: error.message };
    }
  }

  // 개별 시트 분석
  analyzeSheet(sheetId, sheetName) {
    const dimensions = this.hyperFormula.getSheetDimensions(sheetId);
    const analysis = {
      name: sheetName,
      id: sheetId,
      dimensions,
      formulaCount: 0,
      functions: {},
      errors: [],
      dependencies: [],
      dataTypes: { number: 0, text: 0, formula: 0, empty: 0, error: 0 }
    };

    if (!dimensions || dimensions.width === 0 || dimensions.height === 0) {
      return analysis;
    }

    // 각 셀 분석
    for (let row = 0; row < dimensions.height; row++) {
      for (let col = 0; col < dimensions.width; col++) {
        const cellAddress = { sheet: sheetId, row, col };
        
        try {
          const isEmpty = this.hyperFormula.isCellEmpty(cellAddress);
          const hasFormula = this.hyperFormula.doesCellHaveFormula(cellAddress);
          const value = this.hyperFormula.getCellValue(cellAddress);

          if (isEmpty) {
            analysis.dataTypes.empty++;
          } else if (hasFormula) {
            analysis.dataTypes.formula++;
            analysis.formulaCount++;
            
            const formula = this.hyperFormula.getCellFormula(cellAddress);
            this.analyzeFormula(formula, cellAddress, analysis);
          } else {
            if (typeof value === 'number') {
              analysis.dataTypes.number++;
            } else if (typeof value === 'string') {
              if (value.toString().includes('#')) {
                analysis.dataTypes.error++;
                analysis.errors.push({
                  location: `${sheetName}!${row + 1}:${col + 1}`,
                  type: 'cell_error',
                  value: value
                });
              } else {
                analysis.dataTypes.text++;
              }
            }
          }
        } catch (error) {
          analysis.errors.push({
            location: `${sheetName}!${row + 1}:${col + 1}`,
            type: 'analysis_error',
            message: error.message
          });
        }
      }
    }

    return analysis;
  }

  // 개별 수식 분석
  analyzeFormula(formula, cellAddress, analysis) {
    if (!formula) return;

    // 함수 추출
    const functions = this.extractFunctions(formula);
    functions.forEach(func => {
      analysis.functions[func] = (analysis.functions[func] || 0) + 1;
    });

    // 의존성 분석
    try {
      const precedents = this.hyperFormula.getCellPrecedents(cellAddress);
      if (precedents.length > 0) {
        analysis.dependencies.push({
          cell: cellAddress,
          formula: formula,
          dependsOn: precedents.length,
          precedents: precedents
        });
      }
    } catch (error) {
      // 의존성 분석 실패는 무시
    }
  }

  // 수식에서 함수 추출
  extractFunctions(formula) {
    const functionPattern = /([A-Z][A-Z0-9]*)\s*\(/g;
    const functions = [];
    let match;
    
    while ((match = functionPattern.exec(formula)) !== null) {
      functions.push(match[1]);
    }
    
    return [...new Set(functions)]; // 중복 제거
  }

  // 수식 검증
  validateFormula(formula) {
    try {
      const validation = this.hyperFormula.validateFormula(formula);
      return { success: true, valid: validation.valid, errors: validation.errors || [] };
    } catch (error) {
      return { success: false, error: error.message };
    }
  }

  // 수식 계산
  calculateFormula(formula) {
    try {
      const result = this.hyperFormula.calculateFormula(formula, 0);
      return { success: true, result: result };
    } catch (error) {
      return { success: false, error: error.message };
    }
  }

  // 세션 정리
  cleanup() {
    if (this.hyperFormula) {
      this.hyperFormula.destroy();
    }
    this.hyperFormula = null;
    this.sheets.clear();
  }
}

// API 엔드포인트들

// 헬스 체크
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'FormulaEngine',
    version: '1.0.0',
    hyperformulaVersion: HyperFormula.version,
    supportedFunctions: Object.keys(HyperFormula.getRegisteredFunctionNames('enGB')).length,
    activeSessions: sessions.size,
    uptime: process.uptime(),
    memory: process.memoryUsage()
  });
});

// 세션 생성
app.post('/sessions', (req, res) => {
  try {
    const sessionId = require('uuid').v4();
    const engine = new FormulaEngine(sessionId);
    sessions.set(sessionId, engine);
    
    console.log(`📝 새 세션 생성: ${sessionId}`);
    
    res.json({
      success: true,
      sessionId: sessionId,
      message: 'FormulaEngine 세션이 생성되었습니다.'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Excel 데이터 로드
app.post('/sessions/:sessionId/load', (req, res) => {
  try {
    const { sessionId } = req.params;
    const { excelData } = req.body;
    
    const engine = sessions.get(sessionId);
    if (!engine) {
      return res.status(404).json({
        success: false,
        error: '세션을 찾을 수 없습니다.'
      });
    }

    const result = engine.createFromExcelData(excelData);
    
    console.log(`📊 Excel 데이터 로드: ${sessionId}`);
    res.json(result);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 수식 분석
app.get('/sessions/:sessionId/analyze', (req, res) => {
  try {
    const { sessionId } = req.params;
    
    const engine = sessions.get(sessionId);
    if (!engine) {
      return res.status(404).json({
        success: false,
        error: '세션을 찾을 수 없습니다.'
      });
    }

    const result = engine.analyzeFormulas();
    
    console.log(`🔍 수식 분석 수행: ${sessionId}`);
    res.json(result);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 수식 검증
app.post('/sessions/:sessionId/validate', (req, res) => {
  try {
    const { sessionId } = req.params;
    const { formula } = req.body;
    
    const engine = sessions.get(sessionId);
    if (!engine) {
      return res.status(404).json({
        success: false,
        error: '세션을 찾을 수 없습니다.'
      });
    }

    const result = engine.validateFormula(formula);
    res.json(result);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 수식 계산
app.post('/sessions/:sessionId/calculate', (req, res) => {
  try {
    const { sessionId } = req.params;
    const { formula } = req.body;
    
    const engine = sessions.get(sessionId);
    if (!engine) {
      return res.status(404).json({
        success: false,
        error: '세션을 찾을 수 없습니다.'
      });
    }

    const result = engine.calculateFormula(formula);
    res.json(result);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 지원 함수 목록
app.get('/functions', (req, res) => {
  try {
    const functions = Object.values(HyperFormula.getRegisteredFunctionNames('enGB'));
    const categories = {
      MATH: functions.filter(f => ['SUM', 'AVERAGE', 'MAX', 'MIN', 'ABS', 'ROUND', 'SQRT'].includes(f)),
      LOGICAL: functions.filter(f => ['IF', 'AND', 'OR', 'NOT', 'TRUE', 'FALSE'].includes(f)),
      TEXT: functions.filter(f => ['CONCATENATE', 'LEFT', 'RIGHT', 'LEN', 'UPPER', 'LOWER'].includes(f)),
      DATE: functions.filter(f => ['DATE', 'TIME', 'NOW', 'TODAY', 'YEAR', 'MONTH', 'DAY'].includes(f)),
      LOOKUP: functions.filter(f => ['VLOOKUP', 'HLOOKUP', 'INDEX', 'MATCH'].includes(f)),
      STATISTICAL: functions.filter(f => ['COUNT', 'COUNTA', 'COUNTIF', 'SUMIF', 'AVERAGEIF'].includes(f))
    };

    res.json({
      success: true,
      total: functions.length,
      functions: functions.sort(),
      categories: categories
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 세션 삭제
app.delete('/sessions/:sessionId', (req, res) => {
  try {
    const { sessionId } = req.params;
    
    const engine = sessions.get(sessionId);
    if (engine) {
      engine.cleanup();
      sessions.delete(sessionId);
      console.log(`🗑️  세션 삭제: ${sessionId}`);
    }

    res.json({
      success: true,
      message: '세션이 삭제되었습니다.'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ============================================================================
// 🆕 ExcelJS + HyperFormula 통합 API 엔드포인트들
// ============================================================================

// 통합 세션 생성
app.post('/integrated/sessions', (req, res) => {
  try {
    const sessionId = require('uuid').v4();
    const engine = new IntegratedEngine(sessionId, req.body.options || {});
    integratedSessions.set(sessionId, engine);
    
    console.log(`📝 새 통합 세션 생성: ${sessionId}`);
    
    res.json({
      success: true,
      sessionId: sessionId,
      message: '통합 분석 세션이 생성되었습니다.',
      capabilities: [
        'Excel 파일 직접 업로드',
        'ExcelJS + HyperFormula 통합 분석',
        '호환성 검증',
        '성능 측정',
        '분석 보고서 생성'
      ]
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Excel 파일 업로드 및 통합 분석
app.post('/integrated/sessions/:sessionId/analyze-file', upload.single('excelFile'), async (req, res) => {
  try {
    const { sessionId } = req.params;
    const engine = integratedSessions.get(sessionId);
    
    if (!engine) {
      return res.status(404).json({
        success: false,
        error: '통합 세션을 찾을 수 없습니다.'
      });
    }

    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'Excel 파일이 업로드되지 않았습니다.'
      });
    }

    const options = {
      validateCompatibility: req.body.validateCompatibility === 'true',
      compareWithOriginal: req.body.compareWithOriginal === 'true',
      includePerformanceMetrics: req.body.includePerformanceMetrics === 'true'
    };

    console.log(`📊 통합 Excel 파일 분석 시작: ${sessionId} - ${req.file.originalname}`);
    
    const analysisResult = await engine.analyzeExcelFile(req.file.buffer, options);
    
    console.log(`✅ 통합 분석 완료: ${sessionId} (${analysisResult.performance?.totalTime}ms)`);
    
    res.json(analysisResult);
  } catch (error) {
    console.error(`❌ 통합 분석 실패: ${error.message}`);
    res.status(500).json({
      success: false,
      error: error.message,
      type: 'integrated_analysis_error'
    });
  }
});

// ExcelJS ↔ HyperFormula 데이터 변환 테스트
app.post('/integrated/convert/test', upload.single('excelFile'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'Excel 파일이 업로드되지 않았습니다.'
      });
    }

    const converter = new ExcelConverter();
    const testResults = {
      success: true,
      conversions: [],
      performance: {},
      compatibility: {}
    };

    console.log(`🔄 데이터 변환 호환성 테스트 시작: ${req.file.originalname}`);

    // 1. ExcelJS → HyperFormula 변환 테스트
    const conversionResult = await converter.measurePerformance(
      async (data) => await converter.readExcelFile(data),
      req.file.buffer
    );

    testResults.conversions.push({
      direction: 'ExcelJS → HyperFormula',
      success: conversionResult.success,
      performance: conversionResult.performance,
      error: conversionResult.error
    });

    if (conversionResult.success) {
      // 2. HyperFormula → ExcelJS 변환 테스트
      const backConversionResult = await converter.measurePerformance(
        async (data) => await converter.writeExcelFile(data),
        conversionResult.result
      );

      testResults.conversions.push({
        direction: 'HyperFormula → ExcelJS',
        success: backConversionResult.success,
        performance: backConversionResult.performance,
        error: backConversionResult.error
      });

      // 3. 데이터 무결성 검증
      if (backConversionResult.success) {
        const integrityTest = converter.validateDataIntegrity(
          conversionResult.result,
          await converter.readExcelFile(backConversionResult.result)
        );

        testResults.compatibility = integrityTest;
      }
    }

    console.log(`✅ 변환 테스트 완료: ${testResults.conversions.length}개 변환 테스트`);
    
    res.json(testResults);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
      type: 'conversion_test_error'
    });
  }
});

// 분석 보고서 생성 및 다운로드
app.get('/integrated/sessions/:sessionId/report', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const engine = integratedSessions.get(sessionId);
    
    if (!engine) {
      return res.status(404).json({
        success: false,
        error: '통합 세션을 찾을 수 없습니다.'
      });
    }

    const options = {
      includeDetailedAnalysis: req.query.detailed === 'true',
      metadata: {
        title: req.query.title || '수식 분석 보고서',
        creator: req.query.creator || 'FormulaEngine Service'
      }
    };

    console.log(`📄 분석 보고서 생성 시작: ${sessionId}`);
    
    const reportBuffer = await engine.generateAnalysisReport(options);
    
    const filename = `analysis_report_${sessionId}_${new Date().toISOString().split('T')[0]}.xlsx`;
    
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Length', reportBuffer.length);
    
    console.log(`✅ 보고서 생성 완료: ${filename} (${reportBuffer.length} bytes)`);
    
    res.send(reportBuffer);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
      type: 'report_generation_error'
    });
  }
});

// 통합 세션 상태 조회
app.get('/integrated/sessions/:sessionId/status', (req, res) => {
  try {
    const { sessionId } = req.params;
    const engine = integratedSessions.get(sessionId);
    
    if (!engine) {
      return res.status(404).json({
        success: false,
        error: '통합 세션을 찾을 수 없습니다.'
      });
    }

    const status = {
      success: true,
      sessionId: sessionId,
      isActive: !engine.isExpired(),
      lastActivity: new Date(engine.lastActivity).toISOString(),
      hasAnalysisResults: !!engine.analysisResults,
      capabilities: {
        excelParsing: true,
        formulaAnalysis: true,
        compatibilityValidation: true,
        reportGeneration: true
      }
    };

    if (engine.analysisResults) {
      status.lastAnalysis = {
        timestamp: engine.analysisResults.timestamp,
        totalSheets: engine.analysisResults.formulas?.summary?.totalSheets || 0,
        totalFormulas: engine.analysisResults.formulas?.summary?.totalFormulas || 0,
        errorCount: engine.analysisResults.formulas?.summary?.errorCells || 0,
        performanceMs: engine.analysisResults.performance?.totalTime || 0
      };
    }

    engine.updateActivity();
    res.json(status);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 라이브러리 비교 정보
app.get('/integrated/comparison', (req, res) => {
  try {
    const ExcelJS = require('exceljs');
    
    const comparison = {
      success: true,
      libraries: {
        hyperformula: {
          name: 'HyperFormula',
          version: HyperFormula.version,
          purpose: '수식 계산 엔진',
          supportedFunctions: Object.values(HyperFormula.getRegisteredFunctionNames('enGB')).length,
          strengths: [
            'Excel과 동일한 수식 계산',
            '순환 참조 탐지',
            '의존성 관리',
            '고성능 계산 최적화'
          ],
          limitations: [
            'Excel 파일 직접 파싱 불가',
            '서식/스타일 정보 처리 불가',
            '차트, 이미지 등 비지원'
          ]
        },
        exceljs: {
          name: 'ExcelJS',
          version: '4.4.0', // 설치된 버전
          purpose: 'Excel 파일 I/O 및 조작',
          strengths: [
            'Excel 파일 직접 읽기/쓰기',
            '서식, 스타일, 차트 지원',
            '이미지, 도형 처리',
            '워크시트 보호 기능'
          ],
          limitations: [
            '수식 계산 엔진 없음',
            '수식 텍스트로만 저장/읽기',
            '복잡한 수식 분석 제한'
          ]
        }
      },
      integration: {
        workflow: [
          'ExcelJS로 Excel 파일 파싱',
          'ExcelJS → HyperFormula 데이터 변환',
          'HyperFormula로 수식 분석/계산',
          'HyperFormula → ExcelJS 결과 변환',
          'ExcelJS로 Excel 파일 생성'
        ],
        benefits: [
          '완전한 Excel 처리 파이프라인',
          '서식 보존 + 수식 분석',
          '호환성 검증',
          '성능 최적화'
        ]
      }
    };

    res.json(comparison);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 통합 세션 삭제
app.delete('/integrated/sessions/:sessionId', (req, res) => {
  try {
    const { sessionId } = req.params;
    
    const engine = integratedSessions.get(sessionId);
    if (engine) {
      engine.cleanup();
      integratedSessions.delete(sessionId);
      console.log(`🗑️  통합 세션 삭제: ${sessionId}`);
    }

    res.json({
      success: true,
      message: '통합 세션이 삭제되었습니다.'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// 헬스 체크 (확장된 버전)
app.get('/integrated/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'Integrated FormulaEngine (ExcelJS + HyperFormula)',
    version: '2.0.0',
    libraries: {
      hyperformula: HyperFormula.version,
      exceljs: '4.4.0'
    },
    capabilities: [
      'Excel 파일 직접 처리',
      '통합 수식 분석',
      '호환성 검증',
      '성능 측정',
      '보고서 생성'
    ],
    activeSessions: {
      basic: sessions.size,
      integrated: integratedSessions.size,
      total: sessions.size + integratedSessions.size
    },
    supportedFormats: ['xlsx', 'xls', 'csv'],
    maxFileSize: '50MB',
    uptime: process.uptime(),
    memory: process.memoryUsage()
  });
});

// 에러 처리 미들웨어
app.use((error, req, res, next) => {
  console.error('서버 오류:', error);
  res.status(500).json({
    success: false,
    error: 'Internal Server Error',
    message: error.message
  });
});

// 404 처리
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Not Found',
    message: `${req.method} ${req.path} 엔드포인트를 찾을 수 없습니다.`
  });
});

// 정기적으로 비활성 세션 정리 (10분 이상 비활성)
setInterval(() => {
  const now = Date.now();
  const expiredSessions = [];
  const expiredIntegratedSessions = [];
  
  // 기본 세션 정리
  sessions.forEach((engine, sessionId) => {
    if (now - engine.lastActivity > 10 * 60 * 1000) { // 10분
      expiredSessions.push(sessionId);
    }
  });
  
  // 통합 세션 정리
  integratedSessions.forEach((engine, sessionId) => {
    if (engine.isExpired(10 * 60 * 1000)) { // 10분
      expiredIntegratedSessions.push(sessionId);
    }
  });
  
  // 기본 세션 정리 실행
  expiredSessions.forEach(sessionId => {
    const engine = sessions.get(sessionId);
    if (engine) {
      engine.cleanup();
      sessions.delete(sessionId);
      console.log(`⏰ 만료된 기본 세션 정리: ${sessionId}`);
    }
  });
  
  // 통합 세션 정리 실행
  expiredIntegratedSessions.forEach(sessionId => {
    const engine = integratedSessions.get(sessionId);
    if (engine) {
      engine.cleanup();
      integratedSessions.delete(sessionId);
      console.log(`⏰ 만료된 통합 세션 정리: ${sessionId}`);
    }
  });
  
  const totalCleaned = expiredSessions.length + expiredIntegratedSessions.length;
  if (totalCleaned > 0) {
    console.log(`🧹 세션 정리 완료: 기본 ${expiredSessions.length}개, 통합 ${expiredIntegratedSessions.length}개`);
  }
}, 5 * 60 * 1000); // 5분마다 체크

// 서버 시작
app.listen(PORT, () => {
  console.log(`✅ FormulaEngine 서비스 실행 중: http://localhost:${PORT}`);
  console.log(`📚 지원 함수: ${Object.values(HyperFormula.getRegisteredFunctionNames('enGB')).length}개`);
  console.log(`🔧 HyperFormula 버전: ${HyperFormula.version} (최신버전!)`);
  console.log(`🆕 신규 기능: 배치 처리, 평가 제어, 향상된 직렬화`);
  console.log('=' * 50);
});

// 우아한 종료 처리
process.on('SIGINT', () => {
  console.log('\n🛑 Integrated FormulaEngine 서비스 종료 중...');
  
  // 모든 기본 세션 정리
  sessions.forEach((engine, sessionId) => {
    engine.cleanup();
    console.log(`🗑️  기본 세션 정리: ${sessionId}`);
  });
  sessions.clear();
  
  // 모든 통합 세션 정리
  integratedSessions.forEach((engine, sessionId) => {
    engine.cleanup();
    console.log(`🗑️  통합 세션 정리: ${sessionId}`);
  });
  integratedSessions.clear();
  
  console.log('✅ Integrated FormulaEngine 서비스 종료 완료');
  console.log(`🎯 최종 정리: 기본 세션 ${sessions.size}개, 통합 세션 ${integratedSessions.size}개`);
  process.exit(0);
});