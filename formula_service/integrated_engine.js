const ExcelJS = require('exceljs');
const { HyperFormula } = require('hyperformula');
const ExcelConverter = require('./excel_converter');
const multer = require('multer');
const fs = require('fs').promises;
const path = require('path');

/**
 * ExcelJS + HyperFormula 통합 분석 엔진
 * Excel 파일의 완전한 읽기/분석/수정/저장 워크플로우 제공
 */
class IntegratedEngine {
  constructor(sessionId, options = {}) {
    this.sessionId = sessionId;
    this.converter = new ExcelConverter();
    this.hyperFormula = null;
    this.originalWorkbook = null;
    this.analysisResults = null;
    this.lastActivity = Date.now();
    
    // HyperFormula 설정
    this.hfConfig = {
      licenseKey: 'gpl-v3',
      useColumnIndex: true,
      smartRounding: true,
      numberEpsilon: 1e-10,
      dateFormats: ['MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD'],
      timeFormats: ['hh:mm', 'hh:mm:ss.sss'],
      ...options.hyperformula
    };
  }

  /**
   * Excel 파일로부터 통합 분석 수행
   * @param {Buffer} fileBuffer - Excel 파일 버퍼
   * @param {Object} options - 분석 옵션
   * @returns {Promise<Object>} 통합 분석 결과
   */
  async analyzeExcelFile(fileBuffer, options = {}) {
    const startTime = Date.now();
    const analysis = {
      success: false,
      sessionId: this.sessionId,
      timestamp: new Date().toISOString(),
      performance: {},
      steps: [],
      errors: [],
      warnings: []
    };

    try {
      // 1단계: ExcelJS로 파일 파싱
      analysis.steps.push('Excel 파일 파싱 시작');
      const parseStart = Date.now();
      
      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.load(fileBuffer);
      this.originalWorkbook = workbook;
      
      analysis.steps.push(`Excel 파일 파싱 완료 (${Date.now() - parseStart}ms)`);
      analysis.excel = {
        worksheetCount: workbook.worksheets.length,
        worksheetNames: workbook.worksheets.map(ws => ws.name),
        title: workbook.title,
        creator: workbook.creator,
        created: workbook.created,
        modified: workbook.modified
      };

      // 2단계: ExcelJS → HyperFormula 데이터 변환
      analysis.steps.push('데이터 변환 시작');
      const convertStart = Date.now();
      
      const convertedData = this.converter.excelToHyperFormula(workbook);
      
      analysis.steps.push(`데이터 변환 완료 (${Date.now() - convertStart}ms)`);
      analysis.conversion = {
        totalSheets: convertedData.metadata.totalSheets,
        warnings: convertedData.metadata.warnings,
        sheetInfo: {}
      };

      // 각 시트의 변환 정보 수집
      Object.keys(convertedData.metadata).forEach(key => {
        if (key !== 'workbookName' && key !== 'totalSheets' && key !== 'convertedAt' && key !== 'warnings') {
          analysis.conversion.sheetInfo[key] = convertedData.metadata[key];
        }
      });

      // 3단계: HyperFormula 인스턴스 생성
      analysis.steps.push('HyperFormula 엔진 초기화');
      const hfStart = Date.now();
      
      this.hyperFormula = HyperFormula.buildFromSheets(convertedData.sheets, this.hfConfig);
      
      analysis.steps.push(`HyperFormula 엔진 초기화 완료 (${Date.now() - hfStart}ms)`);

      // 4단계: 통합 수식 분석
      analysis.steps.push('통합 수식 분석 시작');
      const analysisStart = Date.now();
      
      const formulaAnalysis = await this.performIntegratedAnalysis(options);
      
      analysis.steps.push(`통합 수식 분석 완료 (${Date.now() - analysisStart}ms)`);
      analysis.formulas = formulaAnalysis;

      // 5단계: 호환성 검증
      if (options.validateCompatibility) {
        analysis.steps.push('호환성 검증 시작');
        const validationStart = Date.now();
        
        const compatibilityCheck = await this.validateCompatibility(convertedData);
        
        analysis.steps.push(`호환성 검증 완료 (${Date.now() - validationStart}ms)`);
        analysis.compatibility = compatibilityCheck;
      }

      // 최종 결과
      analysis.success = true;
      analysis.performance = {
        totalTime: Date.now() - startTime,
        memoryUsage: process.memoryUsage()
      };

      this.analysisResults = analysis;
      this.lastActivity = Date.now();

    } catch (error) {
      analysis.success = false;
      analysis.error = error.message;
      analysis.errors.push({
        step: analysis.steps[analysis.steps.length - 1] || 'Unknown',
        error: error.message,
        stack: error.stack
      });
    }

    return analysis;
  }

  /**
   * 통합 수식 분석 수행
   * @param {Object} options - 분석 옵션
   * @returns {Promise<Object>} 수식 분석 결과
   */
  async performIntegratedAnalysis(options = {}) {
    const analysis = {
      summary: {
        totalSheets: this.hyperFormula.getSheetNames().length,
        totalFormulas: 0,
        totalCells: 0,
        errorCells: 0
      },
      sheets: [],
      functions: {},
      errors: [],
      dependencies: [],
      circularReferences: [],
      performance: {}
    };

    // 각 시트별 분석
    for (const sheetName of this.hyperFormula.getSheetNames()) {
      const sheetId = this.hyperFormula.getSheetId(sheetName);
      const sheetAnalysis = await this.analyzeSheet(sheetId, sheetName, options);
      
      analysis.sheets.push(sheetAnalysis);
      
      // 전체 통계 업데이트
      analysis.summary.totalFormulas += sheetAnalysis.formulaCount;
      analysis.summary.totalCells += sheetAnalysis.cellCount;
      analysis.summary.errorCells += sheetAnalysis.errorCount;
      
      // 함수 사용 통계 병합
      Object.entries(sheetAnalysis.functions).forEach(([func, count]) => {
        analysis.functions[func] = (analysis.functions[func] || 0) + count;
      });
      
      analysis.errors.push(...sheetAnalysis.errors);
      analysis.dependencies.push(...sheetAnalysis.dependencies);
    }

    // 순환 참조 탐지
    analysis.circularReferences = this.detectCircularReferences();

    return analysis;
  }

  /**
   * 개별 시트 분석
   * @param {number} sheetId - 시트 ID
   * @param {string} sheetName - 시트명
   * @param {Object} options - 분석 옵션
   * @returns {Promise<Object>} 시트 분석 결과
   */
  async analyzeSheet(sheetId, sheetName, options = {}) {
    const dimensions = this.hyperFormula.getSheetDimensions(sheetId);
    const analysis = {
      name: sheetName,
      id: sheetId,
      dimensions,
      cellCount: 0,
      formulaCount: 0,
      errorCount: 0,
      functions: {},
      errors: [],
      dependencies: [],
      dataTypes: {
        number: 0,
        text: 0,
        formula: 0,
        boolean: 0,
        date: 0,
        empty: 0,
        error: 0
      },
      complexity: {
        simple: 0,    // 단일 셀 참조, 기본 연산
        medium: 0,    // 범위 참조, 일반 함수
        complex: 0    // 중첩 함수, 다중 시트 참조
      }
    };

    if (!dimensions || dimensions.width === 0 || dimensions.height === 0) {
      return analysis;
    }

    // 원본 Excel 시트 데이터도 함께 분석
    const originalSheet = this.originalWorkbook?.getWorksheet(sheetName);

    // 각 셀 분석
    for (let row = 0; row < dimensions.height; row++) {
      for (let col = 0; col < dimensions.width; col++) {
        const cellAddress = { sheet: sheetId, row, col };
        analysis.cellCount++;
        
        try {
          await this.analyzeCellIntegrated(cellAddress, originalSheet, analysis, options);
        } catch (error) {
          analysis.errors.push({
            location: `${sheetName}!${this.addressToExcel(row, col)}`,
            type: 'cell_analysis_error',
            message: error.message
          });
        }
      }
    }

    return analysis;
  }

  /**
   * 통합 셀 분석 (HyperFormula + ExcelJS)
   * @param {Object} cellAddress - HyperFormula 셀 주소
   * @param {ExcelJS.Worksheet} originalSheet - 원본 ExcelJS 시트
   * @param {Object} analysis - 분석 결과 객체
   * @param {Object} options - 분석 옵션
   */
  async analyzeCellIntegrated(cellAddress, originalSheet, analysis, options) {
    const { row, col } = cellAddress;
    
    // HyperFormula 데이터
    const isEmpty = this.hyperFormula.isCellEmpty(cellAddress);
    const hasFormula = this.hyperFormula.doesCellHaveFormula(cellAddress);
    const value = this.hyperFormula.getCellValue(cellAddress);
    
    // ExcelJS 원본 데이터 (있는 경우)
    let originalCell = null;
    if (originalSheet) {
      originalCell = originalSheet.getCell(row + 1, col + 1);
    }

    if (isEmpty) {
      analysis.dataTypes.empty++;
      return;
    }

    if (hasFormula) {
      analysis.dataTypes.formula++;
      analysis.formulaCount++;
      
      const formula = this.hyperFormula.getCellFormula(cellAddress);
      
      // 수식 복잡도 분석
      const complexity = this.analyzeFormulaComplexity(formula);
      analysis.complexity[complexity]++;
      
      // 함수 추출 및 카운트
      const functions = this.extractFunctions(formula);
      functions.forEach(func => {
        analysis.functions[func] = (analysis.functions[func] || 0) + 1;
      });
      
      // 의존성 분석
      try {
        const precedents = this.hyperFormula.getCellPrecedents(cellAddress);
        if (precedents.length > 0) {
          analysis.dependencies.push({
            cell: this.addressToExcel(row, col),
            formula: formula,
            dependsOn: precedents.length,
            precedents: precedents.map(p => this.addressToExcel(p.row, p.col)),
            complexity: complexity
          });
        }
      } catch (error) {
        // 의존성 분석 실패는 경고로 처리
      }
      
      // 수식 계산 결과 검증
      if (typeof value === 'string' && value.startsWith('#')) {
        analysis.dataTypes.error++;
        analysis.errorCount++;
        analysis.errors.push({
          location: `${analysis.name}!${this.addressToExcel(row, col)}`,
          type: 'formula_error',
          formula: formula,
          error: value,
          originalValue: originalCell?.text || originalCell?.value
        });
      }
    } else {
      // 값 타입 분석
      this.categorizeValueType(value, analysis);
      
      // ExcelJS 원본과 비교 (호환성 검증)
      if (originalCell && options.compareWithOriginal) {
        this.compareWithOriginal(value, originalCell, analysis, row, col);
      }
    }
  }

  /**
   * 수식 복잡도 분석
   * @param {string} formula - 분석할 수식
   * @returns {string} 복잡도 레벨 (simple/medium/complex)
   */
  analyzeFormulaComplexity(formula) {
    if (!formula) return 'simple';
    
    const complexIndicators = [
      /\w+\(/g,           // 함수 개수
      /[A-Z]+\d+:[A-Z]+\d+/g,  // 범위 참조
      /\w+\!/g,           // 다른 시트 참조
      /IF\s*\(/gi,        // 조건문
      /\{.*\}/g           // 배열 수식
    ];
    
    let complexityScore = 0;
    
    complexIndicators.forEach(regex => {
      const matches = formula.match(regex);
      if (matches) {
        complexityScore += matches.length;
      }
    });
    
    // 중첩 함수 탐지
    const functionDepth = this.calculateFunctionDepth(formula);
    complexityScore += functionDepth * 2;
    
    if (complexityScore <= 2) return 'simple';
    if (complexityScore <= 6) return 'medium';
    return 'complex';
  }

  /**
   * 함수 중첩 깊이 계산
   * @param {string} formula - 분석할 수식
   * @returns {number} 중첩 깊이
   */
  calculateFunctionDepth(formula) {
    let maxDepth = 0;
    let currentDepth = 0;
    
    for (let i = 0; i < formula.length; i++) {
      if (formula[i] === '(') {
        currentDepth++;
        maxDepth = Math.max(maxDepth, currentDepth);
      } else if (formula[i] === ')') {
        currentDepth--;
      }
    }
    
    return maxDepth;
  }

  /**
   * 수식에서 함수 추출
   * @param {string} formula - 분석할 수식
   * @returns {Array} 추출된 함수 목록
   */
  extractFunctions(formula) {
    const functionPattern = /([A-Z][A-Z0-9\.]*)\s*\(/g;
    const functions = [];
    let match;
    
    while ((match = functionPattern.exec(formula)) !== null) {
      functions.push(match[1]);
    }
    
    return [...new Set(functions)]; // 중복 제거
  }

  /**
   * 값 타입 분류
   * @param {*} value - 분류할 값
   * @param {Object} analysis - 분석 결과 객체
   */
  categorizeValueType(value, analysis) {
    if (value === null || value === undefined || value === '') {
      analysis.dataTypes.empty++;
    } else if (typeof value === 'number') {
      analysis.dataTypes.number++;
    } else if (typeof value === 'boolean') {
      analysis.dataTypes.boolean++;
    } else if (value instanceof Date) {
      analysis.dataTypes.date++;
    } else if (typeof value === 'string') {
      if (value.startsWith('#')) {
        analysis.dataTypes.error++;
        analysis.errorCount++;
      } else {
        analysis.dataTypes.text++;
      }
    } else {
      analysis.dataTypes.text++;
    }
  }

  /**
   * 원본 ExcelJS 데이터와 비교
   * @param {*} hfValue - HyperFormula 값
   * @param {ExcelJS.Cell} originalCell - 원본 셀
   * @param {Object} analysis - 분석 결과 객체
   * @param {number} row - 행 번호
   * @param {number} col - 열 번호
   */
  compareWithOriginal(hfValue, originalCell, analysis, row, col) {
    const originalValue = originalCell.value;
    
    if (!this.valuesEqual(hfValue, originalValue)) {
      analysis.errors.push({
        location: `${analysis.name}!${this.addressToExcel(row, col)}`,
        type: 'compatibility_mismatch',
        hyperformulaValue: hfValue,
        excelValue: originalValue,
        severity: 'warning'
      });
    }
  }

  /**
   * 값 동등성 검사
   * @param {*} value1 - 첫 번째 값
   * @param {*} value2 - 두 번째 값
   * @returns {boolean} 동등 여부
   */
  valuesEqual(value1, value2) {
    if (value1 === value2) return true;
    if (value1 == null && value2 == null) return true;
    if (value1 == null || value2 == null) return false;
    
    // 숫자 비교 (부동소수점 오차 고려)
    if (typeof value1 === 'number' && typeof value2 === 'number') {
      return Math.abs(value1 - value2) < 1e-10;
    }
    
    // 문자열 비교
    if (typeof value1 === 'string' && typeof value2 === 'string') {
      return value1.toString() === value2.toString();
    }
    
    return false;
  }

  /**
   * 순환 참조 탐지
   * @returns {Array} 순환 참조 목록
   */
  detectCircularReferences() {
    const circularRefs = [];
    
    try {
      // HyperFormula의 내장 순환 참조 탐지 사용
      this.hyperFormula.getSheetNames().forEach(sheetName => {
        const sheetId = this.hyperFormula.getSheetId(sheetName);
        const dimensions = this.hyperFormula.getSheetDimensions(sheetId);
        
        if (!dimensions) return;
        
        for (let row = 0; row < dimensions.height; row++) {
          for (let col = 0; col < dimensions.width; col++) {
            const cellAddress = { sheet: sheetId, row, col };
            
            if (this.hyperFormula.doesCellHaveFormula(cellAddress)) {
              const value = this.hyperFormula.getCellValue(cellAddress);
              
              if (typeof value === 'string' && value === '#CIRCULAR!') {
                circularRefs.push({
                  location: `${sheetName}!${this.addressToExcel(row, col)}`,
                  formula: this.hyperFormula.getCellFormula(cellAddress)
                });
              }
            }
          }
        }
      });
    } catch (error) {
      console.warn('순환 참조 탐지 중 오류:', error.message);
    }
    
    return circularRefs;
  }

  /**
   * 호환성 검증
   * @param {Object} convertedData - 변환된 데이터
   * @returns {Promise<Object>} 호환성 검증 결과
   */
  async validateCompatibility(convertedData) {
    const validation = {
      isCompatible: true,
      issues: [],
      recommendations: [],
      statistics: {
        totalConversions: 0,
        successfulConversions: 0,
        failedConversions: 0,
        dataLossWarnings: 0
      }
    };

    try {
      // HyperFormula 데이터를 다시 ExcelJS로 변환
      const backConverted = this.converter.hyperFormulaToExcel(convertedData);
      
      // 데이터 무결성 검사
      const integrityCheck = this.converter.validateDataIntegrity(
        convertedData, 
        this.converter.excelToHyperFormula(backConverted)
      );
      
      validation.statistics = integrityCheck.statistics;
      validation.issues = integrityCheck.errors;
      validation.recommendations = integrityCheck.warnings;
      validation.isCompatible = integrityCheck.isValid;
      
    } catch (error) {
      validation.isCompatible = false;
      validation.issues.push(`호환성 검증 실패: ${error.message}`);
    }

    return validation;
  }

  /**
   * 분석 결과를 Excel 파일로 저장
   * @param {Object} options - 저장 옵션
   * @returns {Promise<Buffer>} Excel 파일 버퍼
   */
  async generateAnalysisReport(options = {}) {
    if (!this.analysisResults) {
      throw new Error('분석 결과가 없습니다. 먼저 analyzeExcelFile()을 실행하세요.');
    }

    const reportWorkbook = new ExcelJS.Workbook();
    reportWorkbook.title = '수식 분석 보고서';
    reportWorkbook.creator = 'FormulaEngine Service';
    reportWorkbook.created = new Date();

    // 요약 시트
    const summarySheet = reportWorkbook.addWorksheet('분석 요약');
    await this.createSummarySheet(summarySheet);

    // 시트별 상세 분석
    if (options.includeDetailedAnalysis) {
      this.analysisResults.formulas.sheets.forEach(sheetAnalysis => {
        const detailSheet = reportWorkbook.addWorksheet(`상세_${sheetAnalysis.name}`);
        this.createDetailSheet(detailSheet, sheetAnalysis);
      });
    }

    // 오류 및 경고 시트
    if (this.analysisResults.formulas.errors.length > 0) {
      const errorSheet = reportWorkbook.addWorksheet('오류 및 경고');
      this.createErrorSheet(errorSheet);
    }

    return await reportWorkbook.xlsx.writeBuffer();
  }

  /**
   * 요약 시트 생성
   * @param {ExcelJS.Worksheet} sheet - 워크시트
   */
  async createSummarySheet(sheet) {
    const analysis = this.analysisResults;
    
    // 헤더
    sheet.addRow(['ExcelJS + HyperFormula 통합 분석 보고서']);
    sheet.addRow(['생성일시', new Date().toLocaleString('ko-KR')]);
    sheet.addRow(['세션 ID', this.sessionId]);
    sheet.addRow([]);

    // 기본 정보
    sheet.addRow(['기본 정보']);
    sheet.addRow(['총 시트 수', analysis.formulas.summary.totalSheets]);
    sheet.addRow(['총 셀 수', analysis.formulas.summary.totalCells]);
    sheet.addRow(['총 수식 수', analysis.formulas.summary.totalFormulas]);
    sheet.addRow(['오류 셀 수', analysis.formulas.summary.errorCells]);
    sheet.addRow([]);

    // 성능 정보
    sheet.addRow(['성능 정보']);
    sheet.addRow(['총 처리 시간', `${analysis.performance.totalTime}ms`]);
    sheet.addRow(['메모리 사용량', `${Math.round(analysis.performance.memoryUsage.heapUsed / 1024 / 1024)}MB`]);
    sheet.addRow([]);

    // 함수 사용 통계
    sheet.addRow(['함수 사용 통계']);
    sheet.addRow(['함수명', '사용 횟수']);
    
    Object.entries(analysis.formulas.functions)
      .sort(([,a], [,b]) => b - a)
      .slice(0, 20) // 상위 20개만
      .forEach(([func, count]) => {
        sheet.addRow([func, count]);
      });

    // 스타일 적용
    sheet.getCell('A1').font = { bold: true, size: 14 };
    sheet.getColumn('A').width = 20;
    sheet.getColumn('B').width = 30;
  }

  /**
   * 상세 분석 시트 생성
   * @param {ExcelJS.Worksheet} sheet - 워크시트
   * @param {Object} sheetAnalysis - 시트 분석 결과
   */
  createDetailSheet(sheet, sheetAnalysis) {
    // 시트 기본 정보
    sheet.addRow([`시트: ${sheetAnalysis.name}`]);
    sheet.addRow(['크기', `${sheetAnalysis.dimensions.width} x ${sheetAnalysis.dimensions.height}`]);
    sheet.addRow(['셀 수', sheetAnalysis.cellCount]);
    sheet.addRow(['수식 수', sheetAnalysis.formulaCount]);
    sheet.addRow([]);

    // 데이터 타입 분포
    sheet.addRow(['데이터 타입 분포']);
    Object.entries(sheetAnalysis.dataTypes).forEach(([type, count]) => {
      if (count > 0) {
        sheet.addRow([type, count]);
      }
    });
    sheet.addRow([]);

    // 복잡도 분석
    sheet.addRow(['수식 복잡도']);
    sheet.addRow(['단순', sheetAnalysis.complexity.simple]);
    sheet.addRow(['보통', sheetAnalysis.complexity.medium]);
    sheet.addRow(['복잡', sheetAnalysis.complexity.complex]);
    sheet.addRow([]);

    // 의존성 정보
    if (sheetAnalysis.dependencies.length > 0) {
      sheet.addRow(['의존성 정보']);
      sheet.addRow(['셀', '수식', '의존 개수', '복잡도']);
      
      sheetAnalysis.dependencies.forEach(dep => {
        sheet.addRow([dep.cell, dep.formula, dep.dependsOn, dep.complexity]);
      });
    }
  }

  /**
   * 오류 시트 생성
   * @param {ExcelJS.Worksheet} sheet - 워크시트
   */
  createErrorSheet(sheet) {
    sheet.addRow(['오류 및 경고 목록']);
    sheet.addRow(['위치', '타입', '내용', '수식/값']);
    
    this.analysisResults.formulas.errors.forEach(error => {
      sheet.addRow([
        error.location,
        error.type,
        error.message || error.error,
        error.formula || error.originalValue || ''
      ]);
    });

    // 헤더 스타일
    const headerRow = sheet.getRow(2);
    headerRow.font = { bold: true };
    headerRow.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FFE0E0E0' }
    };
  }

  /**
   * 행/열 번호를 Excel 주소로 변환
   * @param {number} row - 0 기반 행 번호
   * @param {number} col - 0 기반 열 번호
   * @returns {string} Excel 주소 (예: A1)
   */
  addressToExcel(row, col) {
    let colStr = '';
    let colNum = col + 1;
    
    while (colNum > 0) {
      colNum--;
      colStr = String.fromCharCode(65 + (colNum % 26)) + colStr;
      colNum = Math.floor(colNum / 26);
    }
    
    return colStr + (row + 1);
  }

  /**
   * 리소스 정리
   */
  cleanup() {
    if (this.hyperFormula) {
      this.hyperFormula.destroy();
      this.hyperFormula = null;
    }
    
    this.originalWorkbook = null;
    this.analysisResults = null;
    this.converter = null;
  }

  /**
   * 세션 활성화 시간 업데이트
   */
  updateActivity() {
    this.lastActivity = Date.now();
  }

  /**
   * 세션이 만료되었는지 확인
   * @param {number} timeoutMs - 타임아웃 시간 (밀리초)
   * @returns {boolean} 만료 여부
   */
  isExpired(timeoutMs = 10 * 60 * 1000) {
    return (Date.now() - this.lastActivity) > timeoutMs;
  }
}

module.exports = IntegratedEngine;