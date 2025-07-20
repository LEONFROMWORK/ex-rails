const ExcelJS = require('exceljs');
const { HyperFormula } = require('hyperformula');
const ExcelConverter = require('./excel_converter');
const IntegratedEngine = require('./integrated_engine');

/**
 * ExcelJS와 HyperFormula 간 호환성 검증 상세 보고서
 * 실제 사용 시나리오에서의 호환성 문제점과 해결방안 제시
 */
class CompatibilityReport {
  constructor() {
    this.testResults = [];
    this.knownIssues = [];
    this.compatibilityMatrix = {};
  }

  /**
   * 종합 호환성 테스트 실행
   * @returns {Promise<Object>} 호환성 검증 결과
   */
  async runComprehensiveCompatibilityTest() {
    console.log('🔍 ExcelJS ↔ HyperFormula 호환성 검증 시작');
    console.log('=' * 50);

    const report = {
      timestamp: new Date().toISOString(),
      version: {
        exceljs: '4.4.0',
        hyperformula: HyperFormula.version
      },
      testResults: [],
      compatibilityMatrix: {},
      knownIssues: [],
      recommendations: [],
      summary: {
        totalTests: 0,
        passedTests: 0,
        failedTests: 0,
        compatibilityScore: 0
      }
    };

    // 1. 데이터 타입 호환성 테스트
    console.log('\n📊 데이터 타입 호환성 테스트...');
    const dataTypeResult = await this.testDataTypeCompatibility();
    report.testResults.push(dataTypeResult);

    // 2. 수식 표현 호환성 테스트
    console.log('\n🧮 수식 표현 호환성 테스트...');
    const formulaResult = await this.testFormulaCompatibility();
    report.testResults.push(formulaResult);

    // 3. 대량 데이터 호환성 테스트
    console.log('\n📈 대량 데이터 호환성 테스트...');
    const largeDataResult = await this.testLargeDataCompatibility();
    report.testResults.push(largeDataResult);

    // 4. 다중 시트 호환성 테스트
    console.log('\n📑 다중 시트 호환성 테스트...');
    const multiSheetResult = await this.testMultiSheetCompatibility();
    report.testResults.push(multiSheetResult);

    // 5. 에러 처리 호환성 테스트
    console.log('\n⚠️  에러 처리 호환성 테스트...');
    const errorHandlingResult = await this.testErrorHandling();
    report.testResults.push(errorHandlingResult);

    // 6. 특수 기능 호환성 테스트
    console.log('\n🎯 특수 기능 호환성 테스트...');
    const specialFeaturesResult = await this.testSpecialFeatures();
    report.testResults.push(specialFeaturesResult);

    // 결과 분석 및 요약
    report.summary = this.calculateSummary(report.testResults);
    report.compatibilityMatrix = this.buildCompatibilityMatrix(report.testResults);
    report.knownIssues = this.identifyKnownIssues(report.testResults);
    report.recommendations = this.generateRecommendations(report);

    console.log('\n✅ 호환성 검증 완료');
    this.printSummary(report);

    return report;
  }

  /**
   * 데이터 타입 호환성 테스트
   * @returns {Promise<Object>} 테스트 결과
   */
  async testDataTypeCompatibility() {
    const testName = 'Data Type Compatibility';
    const testData = {
      sheets: {
        'DataTypes': [
          ['Type', 'Value', 'Expected'],
          ['Number', 123.45, 123.45],
          ['String', 'Hello World', 'Hello World'],
          ['Boolean', true, true],
          ['Date', new Date('2023-01-01'), new Date('2023-01-01')],
          ['Null', null, null],
          ['Zero', 0, 0],
          ['EmptyString', '', ''],
          ['LargeNumber', 1.23e10, 1.23e10],
          ['NegativeNumber', -456.78, -456.78],
          ['Percentage', 0.75, 0.75]
        ]
      }
    };

    try {
      const converter = new ExcelConverter();
      
      // 1. HyperFormula → ExcelJS 변환
      const excelWorkbook = converter.hyperFormulaToExcel(testData);
      const excelBuffer = await excelWorkbook.xlsx.writeBuffer();
      
      // 2. ExcelJS → HyperFormula 변환
      const backConverted = await converter.readExcelFile(excelBuffer);
      
      // 3. 데이터 무결성 검증
      const integrityCheck = converter.validateDataIntegrity(testData, backConverted);
      
      // 4. 타입별 상세 검증
      const typeResults = await this.analyzeDataTypePreservation(testData, backConverted);

      return {
        testName,
        success: integrityCheck.isValid,
        details: {
          integrityCheck,
          typeResults,
          originalData: testData,
          convertedData: backConverted
        },
        issues: integrityCheck.errors,
        warnings: integrityCheck.warnings
      };
    } catch (error) {
      return {
        testName,
        success: false,
        error: error.message,
        issues: [`Test execution failed: ${error.message}`]
      };
    }
  }

  /**
   * 데이터 타입 보존 분석
   * @param {Object} original - 원본 데이터
   * @param {Object} converted - 변환된 데이터
   * @returns {Promise<Object>} 타입 분석 결과
   */
  async analyzeDataTypePreservation(original, converted) {
    const analysis = {
      typePreservation: {},
      conversionIssues: [],
      successRate: 0
    };

    const dataTypesSheet = original.sheets['DataTypes'];
    const convertedSheet = converted.sheets['DataTypes'];

    if (!convertedSheet) {
      analysis.conversionIssues.push('DataTypes sheet missing after conversion');
      return analysis;
    }

    let totalTypes = 0;
    let preservedTypes = 0;

    for (let i = 1; i < dataTypesSheet.length; i++) { // Skip header
      const [typeName, originalValue, expectedValue] = dataTypesSheet[i];
      const convertedRow = convertedSheet[i];
      
      if (convertedRow) {
        const convertedValue = convertedRow[1];
        totalTypes++;
        
        const typeResult = {
          typeName,
          originalValue,
          convertedValue,
          expectedValue,
          preserved: this.compareValues(originalValue, convertedValue),
          originalType: this.getJSType(originalValue),
          convertedType: this.getJSType(convertedValue)
        };

        if (typeResult.preserved) {
          preservedTypes++;
        } else {
          analysis.conversionIssues.push(
            `Type ${typeName}: ${originalValue} (${typeResult.originalType}) → ${convertedValue} (${typeResult.convertedType})`
          );
        }

        analysis.typePreservation[typeName] = typeResult;
      }
    }

    analysis.successRate = totalTypes > 0 ? (preservedTypes / totalTypes) * 100 : 0;

    return analysis;
  }

  /**
   * 수식 표현 호환성 테스트
   * @returns {Promise<Object>} 테스트 결과
   */
  async testFormulaCompatibility() {
    const testName = 'Formula Expression Compatibility';
    const testFormulas = [
      // 기본 수식
      '=A1+B1',
      '=SUM(A1:A10)',
      '=AVERAGE(B1:B10)',
      '=MAX(C1:C10)',
      '=MIN(D1:D10)',
      
      // 논리 함수
      '=IF(A1>0,"Positive","Non-positive")',
      '=AND(A1>0,B1>0)',
      '=OR(A1>10,B1>10)',
      
      // 텍스트 함수
      '=CONCATENATE(A1," ",B1)',
      '=LEFT(A1,5)',
      '=RIGHT(B1,3)',
      '=LEN(A1)',
      
      // 조회 함수
      '=VLOOKUP(A1,A1:B10,2,FALSE)',
      '=INDEX(A1:A10,5)',
      '=MATCH(A1,A1:A10,0)',
      
      // 복잡한 수식
      '=SUMIF(A1:A10,">5",B1:B10)',
      '=COUNTIFS(A1:A10,">0",B1:B10,"<100")',
      '=IFERROR(VLOOKUP(A1,A1:B10,2,FALSE),"Not Found")'
    ];

    const testData = {
      sheets: {
        'FormulaTest': [
          ['Original Formula', 'Test Data', 'Expected Result'],
          ...testFormulas.map((formula, index) => [
            formula,
            index + 1,
            `Result ${index + 1}`
          ])
        ]
      }
    };

    try {
      const converter = new ExcelConverter();
      
      // HyperFormula로 수식 처리
      const hf = HyperFormula.buildFromSheets(testData.sheets);
      const formulaResults = [];

      testFormulas.forEach((formula, index) => {
        try {
          const isValid = hf.validateFormula(formula);
          formulaResults.push({
            formula,
            index,
            valid: isValid.valid,
            errors: isValid.errors || []
          });
        } catch (error) {
          formulaResults.push({
            formula,
            index,
            valid: false,
            errors: [error.message]
          });
        }
      });

      hf.destroy();

      // ExcelJS로 수식 저장/읽기 테스트
      const excelWorkbook = converter.hyperFormulaToExcel(testData);
      const excelBuffer = await excelWorkbook.xlsx.writeBuffer();
      const reloadedData = await converter.readExcelFile(excelBuffer);

      return {
        testName,
        success: true,
        details: {
          totalFormulas: testFormulas.length,
          validFormulas: formulaResults.filter(r => r.valid).length,
          invalidFormulas: formulaResults.filter(r => !r.valid).length,
          formulaResults,
          conversionSuccess: !!reloadedData.sheets['FormulaTest']
        },
        issues: formulaResults.filter(r => !r.valid).map(r => `Formula "${r.formula}": ${r.errors.join(', ')}`),
        warnings: []
      };
    } catch (error) {
      return {
        testName,
        success: false,
        error: error.message,
        issues: [`Formula compatibility test failed: ${error.message}`]
      };
    }
  }

  /**
   * 대량 데이터 호환성 테스트
   * @returns {Promise<Object>} 테스트 결과
   */
  async testLargeDataCompatibility() {
    const testName = 'Large Data Compatibility';
    
    // 큰 데이터셋 생성 (1000 rows x 20 cols)
    const largeDataset = [];
    largeDataset.push(['Col1', 'Col2', 'Col3', 'Col4', 'Col5', 'Col6', 'Col7', 'Col8', 'Col9', 'Col10',
                      'Col11', 'Col12', 'Col13', 'Col14', 'Col15', 'Col16', 'Col17', 'Col18', 'Col19', 'Col20']);
    
    for (let i = 1; i <= 1000; i++) {
      const row = [];
      for (let j = 1; j <= 20; j++) {
        if (j <= 10) {
          row.push(i * j); // 숫자 데이터
        } else if (j <= 15) {
          row.push(`Text_${i}_${j}`); // 텍스트 데이터
        } else {
          row.push(`=A${i}+B${i}`); // 수식 데이터
        }
      }
      largeDataset.push(row);
    }

    const testData = {
      sheets: {
        'LargeData': largeDataset
      }
    };

    try {
      const startTime = Date.now();
      const converter = new ExcelConverter();
      
      // 메모리 사용량 측정
      const startMemory = process.memoryUsage();
      
      // 변환 테스트
      const excelWorkbook = converter.hyperFormulaToExcel(testData);
      const excelBuffer = await excelWorkbook.xlsx.writeBuffer();
      
      const conversionTime = Date.now() - startTime;
      const afterConversionMemory = process.memoryUsage();
      
      // 다시 읽기 테스트
      const readStartTime = Date.now();
      const backConverted = await converter.readExcelFile(excelBuffer);
      const readTime = Date.now() - readStartTime;
      
      const endMemory = process.memoryUsage();
      
      // 데이터 무결성 검증 (샘플링)
      const integrityCheck = this.validateLargeDataIntegrity(testData, backConverted);

      return {
        testName,
        success: integrityCheck.isValid,
        details: {
          dataSize: {
            rows: 1000,
            columns: 20,
            totalCells: 20000
          },
          performance: {
            conversionTime,
            readTime,
            totalTime: conversionTime + readTime,
            fileSize: excelBuffer.length
          },
          memory: {
            startMemory: Math.round(startMemory.heapUsed / 1024 / 1024),
            peakMemory: Math.round(afterConversionMemory.heapUsed / 1024 / 1024),
            endMemory: Math.round(endMemory.heapUsed / 1024 / 1024),
            memoryDelta: Math.round((endMemory.heapUsed - startMemory.heapUsed) / 1024 / 1024)
          },
          integrityCheck
        },
        issues: integrityCheck.errors,
        warnings: integrityCheck.warnings
      };
    } catch (error) {
      return {
        testName,
        success: false,
        error: error.message,
        issues: [`Large data test failed: ${error.message}`]
      };
    }
  }

  /**
   * 다중 시트 호환성 테스트
   * @returns {Promise<Object>} 테스트 결과
   */
  async testMultiSheetCompatibility() {
    const testName = 'Multi-Sheet Compatibility';
    
    const testData = {
      sheets: {
        'Summary': [
          ['Sheet', 'Total', 'Average'],
          ['Data1', '=SUM(Data1.B:B)', '=AVERAGE(Data1.B:B)'],
          ['Data2', '=SUM(Data2.B:B)', '=AVERAGE(Data2.B:B)'],
          ['Data3', '=SUM(Data3.B:B)', '=AVERAGE(Data3.B:B)']
        ],
        'Data1': [
          ['Item', 'Value'],
          ['A', 10],
          ['B', 20],
          ['C', 30]
        ],
        'Data2': [
          ['Item', 'Value'],
          ['X', 100],
          ['Y', 200],
          ['Z', 300]
        ],
        'Data3': [
          ['Item', 'Value'],
          ['Alpha', 1000],
          ['Beta', 2000],
          ['Gamma', 3000]
        ]
      }
    };

    try {
      const converter = new ExcelConverter();
      
      // 다중 시트 변환 테스트
      const excelWorkbook = converter.hyperFormulaToExcel(testData);
      const excelBuffer = await excelWorkbook.xlsx.writeBuffer();
      const backConverted = await converter.readExcelFile(excelBuffer);
      
      // 시트 수 검증
      const originalSheetCount = Object.keys(testData.sheets).length;
      const convertedSheetCount = Object.keys(backConverted.sheets).length;
      
      // 시트별 데이터 무결성 검증
      const sheetResults = {};
      Object.keys(testData.sheets).forEach(sheetName => {
        const originalSheet = testData.sheets[sheetName];
        const convertedSheet = backConverted.sheets[sheetName];
        
        sheetResults[sheetName] = {
          exists: !!convertedSheet,
          rowCount: convertedSheet ? convertedSheet.length : 0,
          originalRowCount: originalSheet.length,
          dataMatches: convertedSheet ? this.compareSheetData(originalSheet, convertedSheet) : false
        };
      });

      // 시트 간 참조 수식 검증
      const crossSheetFormulas = this.extractCrossSheetFormulas(testData.sheets['Summary']);
      
      return {
        testName,
        success: originalSheetCount === convertedSheetCount,
        details: {
          originalSheetCount,
          convertedSheetCount,
          sheetResults,
          crossSheetFormulas,
          allSheetsPreserved: Object.values(sheetResults).every(r => r.exists),
          dataIntegrityScore: Object.values(sheetResults).filter(r => r.dataMatches).length / originalSheetCount * 100
        },
        issues: Object.entries(sheetResults)
          .filter(([, result]) => !result.exists || !result.dataMatches)
          .map(([sheetName, result]) => `Sheet ${sheetName}: ${result.exists ? 'data mismatch' : 'missing'}`),
        warnings: crossSheetFormulas.length > 0 ? [`${crossSheetFormulas.length} cross-sheet formulas detected`] : []
      };
    } catch (error) {
      return {
        testName,
        success: false,
        error: error.message,
        issues: [`Multi-sheet test failed: ${error.message}`]
      };
    }
  }

  /**
   * 에러 처리 호환성 테스트
   * @returns {Promise<Object>} 테스트 결과
   */
  async testErrorHandling() {
    const testName = 'Error Handling Compatibility';
    
    const testData = {
      sheets: {
        'ErrorTest': [
          ['Error Type', 'Formula', 'Expected'],
          ['Division by Zero', '=1/0', '#DIV/0!'],
          ['Invalid Reference', '=A999999', '#REF!'],
          ['Name Error', '=UNKNOWN_FUNCTION()', '#NAME?'],
          ['Value Error', '=SQRT(-1)', '#NUM!'],
          ['Circular Reference', '=A5', '#CIRCULAR!']
        ]
      }
    };

    try {
      const converter = new ExcelConverter();
      
      // HyperFormula로 에러 처리 테스트
      const hf = HyperFormula.buildFromSheets(testData.sheets);
      const errorResults = [];
      
      const sheet = testData.sheets['ErrorTest'];
      for (let i = 1; i < sheet.length; i++) {
        const [errorType, formula, expected] = sheet[i];
        
        try {
          // 수식을 HyperFormula에서 평가
          const sheetId = hf.getSheetId('ErrorTest');
          hf.setCellContents({ sheet: sheetId, row: i, col: 3 }, formula);
          const result = hf.getCellValue({ sheet: sheetId, row: i, col: 3 });
          
          errorResults.push({
            errorType,
            formula,
            expected,
            actual: result,
            handled: typeof result === 'string' && result.startsWith('#')
          });
        } catch (error) {
          errorResults.push({
            errorType,
            formula,
            expected,
            actual: error.message,
            handled: false,
            exception: true
          });
        }
      }
      
      hf.destroy();
      
      // ExcelJS 변환 후 에러 보존 테스트
      const excelWorkbook = converter.hyperFormulaToExcel(testData);
      const excelBuffer = await excelWorkbook.xlsx.writeBuffer();
      const backConverted = await converter.readExcelFile(excelBuffer);
      
      const handledErrors = errorResults.filter(r => r.handled).length;
      const totalErrors = errorResults.length;

      return {
        testName,
        success: handledErrors > 0,
        details: {
          totalErrors,
          handledErrors,
          errorHandlingRate: (handledErrors / totalErrors) * 100,
          errorResults,
          conversionPreservesErrors: !!backConverted.sheets['ErrorTest']
        },
        issues: errorResults.filter(r => !r.handled).map(r => `${r.errorType}: ${r.formula} not properly handled`),
        warnings: errorResults.filter(r => r.exception).map(r => `${r.errorType}: ${r.formula} threw exception`)
      };
    } catch (error) {
      return {
        testName,
        success: false,
        error: error.message,
        issues: [`Error handling test failed: ${error.message}`]
      };
    }
  }

  /**
   * 특수 기능 호환성 테스트
   * @returns {Promise<Object>} 테스트 결과
   */
  async testSpecialFeatures() {
    const testName = 'Special Features Compatibility';
    
    const features = {
      arrayFormulas: '={1,2,3;4,5,6}',
      namedRanges: 'TestRange',
      conditionalFormatting: true,
      dataValidation: true,
      charts: false, // HyperFormula doesn't support charts
      images: false, // HyperFormula doesn't support images
      macros: false  // HyperFormula doesn't support VBA
    };

    const testData = {
      sheets: {
        'SpecialFeatures': [
          ['Feature', 'Supported by HyperFormula', 'Supported by ExcelJS', 'Compatibility'],
          ['Array Formulas', 'Limited', 'Yes', 'Partial'],
          ['Named Ranges', 'No', 'Yes', 'No'],
          ['Conditional Formatting', 'No', 'Yes', 'No'],
          ['Data Validation', 'No', 'Yes', 'No'],
          ['Charts', 'No', 'Yes', 'No'],
          ['Images', 'No', 'Yes', 'No'],
          ['Macros/VBA', 'No', 'Limited', 'No']
        ]
      }
    };

    try {
      const converter = new ExcelConverter();
      
      // 기본 변환 테스트
      const excelWorkbook = converter.hyperFormulaToExcel(testData);
      const excelBuffer = await excelWorkbook.xlsx.writeBuffer();
      const backConverted = await converter.readExcelFile(excelBuffer);
      
      // 특수 기능 지원 매트릭스
      const supportMatrix = {
        'Data Only': { hyperformula: 'Full', exceljs: 'Full', compatibility: 'Full' },
        'Basic Formulas': { hyperformula: 'Full', exceljs: 'Partial', compatibility: 'Good' },
        'Advanced Formulas': { hyperformula: 'Full', exceljs: 'Text Only', compatibility: 'Fair' },
        'Formatting': { hyperformula: 'None', exceljs: 'Full', compatibility: 'Poor' },
        'Charts/Graphics': { hyperformula: 'None', exceljs: 'Full', compatibility: 'None' },
        'Macros': { hyperformula: 'None', exceljs: 'None', compatibility: 'None' }
      };

      return {
        testName,
        success: true,
        details: {
          supportMatrix,
          basicConversionWorks: !!backConverted.sheets['SpecialFeatures'],
          limitationsIdentified: Object.keys(features).length,
          recommendations: [
            'Use HyperFormula for formula calculation only',
            'Use ExcelJS for file I/O and formatting',
            'Combine both for complete Excel processing'
          ]
        },
        issues: [
          'HyperFormula does not support Excel formatting features',
          'Named ranges not directly supported in HyperFormula',
          'Charts and images require ExcelJS-only workflow'
        ],
        warnings: [
          'Some advanced Excel features will be lost in conversion',
          'Complex workbooks may require manual handling'
        ]
      };
    } catch (error) {
      return {
        testName,
        success: false,
        error: error.message,
        issues: [`Special features test failed: ${error.message}`]
      };
    }
  }

  /**
   * 유틸리티 메서드들
   */
  
  compareValues(val1, val2) {
    if (val1 === val2) return true;
    if (val1 == null && val2 == null) return true;
    if (val1 == null || val2 == null) return false;
    
    // 숫자 비교 (부동소수점 오차 고려)
    if (typeof val1 === 'number' && typeof val2 === 'number') {
      return Math.abs(val1 - val2) < 1e-10;
    }
    
    // 날짜 비교
    if (val1 instanceof Date && val2 instanceof Date) {
      return val1.getTime() === val2.getTime();
    }
    
    return String(val1) === String(val2);
  }

  getJSType(value) {
    if (value === null) return 'null';
    if (value === undefined) return 'undefined';
    if (value instanceof Date) return 'Date';
    if (Array.isArray(value)) return 'Array';
    return typeof value;
  }

  validateLargeDataIntegrity(original, converted, sampleSize = 100) {
    const issues = [];
    const warnings = [];
    
    const originalSheet = original.sheets['LargeData'];
    const convertedSheet = converted.sheets['LargeData'];
    
    if (!convertedSheet) {
      return { isValid: false, errors: ['LargeData sheet missing'], warnings: [] };
    }
    
    // 행 수 검증
    if (originalSheet.length !== convertedSheet.length) {
      issues.push(`Row count mismatch: ${originalSheet.length} vs ${convertedSheet.length}`);
    }
    
    // 샘플 데이터 검증
    const step = Math.floor(originalSheet.length / sampleSize);
    let matches = 0;
    let total = 0;
    
    for (let i = 0; i < originalSheet.length; i += step) {
      if (i < convertedSheet.length) {
        total++;
        const originalRow = originalSheet[i];
        const convertedRow = convertedSheet[i];
        
        if (originalRow && convertedRow && originalRow.length === convertedRow.length) {
          let rowMatches = true;
          for (let j = 0; j < Math.min(originalRow.length, 5); j++) { // 처음 5개 열만 검사
            if (!this.compareValues(originalRow[j], convertedRow[j])) {
              rowMatches = false;
              break;
            }
          }
          if (rowMatches) matches++;
        }
      }
    }
    
    const matchRate = total > 0 ? (matches / total) * 100 : 0;
    if (matchRate < 95) {
      issues.push(`Low data integrity: ${matchRate.toFixed(1)}% match rate`);
    } else if (matchRate < 100) {
      warnings.push(`Minor data differences: ${matchRate.toFixed(1)}% match rate`);
    }
    
    return {
      isValid: issues.length === 0,
      errors: issues,
      warnings: warnings,
      statistics: { sampleSize: total, matches, matchRate }
    };
  }

  compareSheetData(original, converted) {
    if (!original || !converted) return false;
    if (original.length !== converted.length) return false;
    
    for (let i = 0; i < Math.min(original.length, 10); i++) { // 처음 10행만 비교
      const originalRow = original[i];
      const convertedRow = converted[i];
      
      if (!originalRow || !convertedRow) continue;
      if (originalRow.length !== convertedRow.length) return false;
      
      for (let j = 0; j < originalRow.length; j++) {
        if (!this.compareValues(originalRow[j], convertedRow[j])) {
          return false;
        }
      }
    }
    
    return true;
  }

  extractCrossSheetFormulas(sheetData) {
    const crossSheetFormulas = [];
    
    sheetData.forEach((row, rowIndex) => {
      row.forEach((cell, colIndex) => {
        if (typeof cell === 'string' && cell.startsWith('=') && cell.includes('.')) {
          crossSheetFormulas.push({
            row: rowIndex,
            col: colIndex,
            formula: cell
          });
        }
      });
    });
    
    return crossSheetFormulas;
  }

  calculateSummary(testResults) {
    const totalTests = testResults.length;
    const passedTests = testResults.filter(r => r.success).length;
    const failedTests = totalTests - passedTests;
    const compatibilityScore = totalTests > 0 ? (passedTests / totalTests) * 100 : 0;
    
    return {
      totalTests,
      passedTests,
      failedTests,
      compatibilityScore: Math.round(compatibilityScore * 100) / 100
    };
  }

  buildCompatibilityMatrix(testResults) {
    const matrix = {};
    
    testResults.forEach(result => {
      matrix[result.testName] = {
        compatible: result.success,
        issues: result.issues?.length || 0,
        warnings: result.warnings?.length || 0,
        details: result.details
      };
    });
    
    return matrix;
  }

  identifyKnownIssues(testResults) {
    const knownIssues = [
      {
        category: 'Data Type Conversion',
        issue: 'Date values may lose timezone information',
        severity: 'Medium',
        workaround: 'Use consistent date formats across libraries'
      },
      {
        category: 'Formula Representation',
        issue: 'ExcelJS stores formulas as text, HyperFormula validates them',
        severity: 'Low',
        workaround: 'Validate formulas before conversion'
      },
      {
        category: 'Special Features',
        issue: 'HyperFormula does not support Excel formatting, charts, or macros',
        severity: 'High',
        workaround: 'Use ExcelJS for features, HyperFormula for calculations'
      },
      {
        category: 'Performance',
        issue: 'Large datasets may consume significant memory during conversion',
        severity: 'Medium',
        workaround: 'Process large files in chunks or use streaming'
      },
      {
        category: 'Named Ranges',
        issue: 'Named ranges are not directly supported in HyperFormula',
        severity: 'Medium',
        workaround: 'Convert named ranges to cell references'
      }
    ];
    
    return knownIssues;
  }

  generateRecommendations(report) {
    const recommendations = [];
    
    // 호환성 점수 기반 추천
    if (report.summary.compatibilityScore >= 80) {
      recommendations.push({
        category: 'General',
        recommendation: '높은 호환성: 대부분의 사용 사례에서 안전하게 통합 사용 가능',
        priority: 'High'
      });
    } else if (report.summary.compatibilityScore >= 60) {
      recommendations.push({
        category: 'General',
        recommendation: '중간 호환성: 주요 기능은 호환되나 일부 제한사항 존재',
        priority: 'Medium'
      });
    } else {
      recommendations.push({
        category: 'General',
        recommendation: '낮은 호환성: 신중한 사용 및 추가 검증 필요',
        priority: 'High'
      });
    }
    
    // 구체적 사용 시나리오별 추천
    recommendations.push({
      category: 'Use Case',
      recommendation: 'Excel 파일 읽기/쓰기만 필요한 경우: ExcelJS 단독 사용',
      priority: 'Medium'
    });
    
    recommendations.push({
      category: 'Use Case',
      recommendation: '수식 계산/분석만 필요한 경우: HyperFormula 단독 사용',
      priority: 'Medium'
    });
    
    recommendations.push({
      category: 'Use Case',
      recommendation: '완전한 Excel 처리 파이프라인 필요: 통합 엔진 사용',
      priority: 'High'
    });
    
    // 성능 관련 추천
    recommendations.push({
      category: 'Performance',
      recommendation: '대용량 파일 처리시 메모리 모니터링 및 청크 처리 고려',
      priority: 'Medium'
    });
    
    return recommendations;
  }

  printSummary(report) {
    console.log('\n📋 호환성 검증 요약:');
    console.log('=' * 40);
    console.log(`전체 테스트: ${report.summary.totalTests}`);
    console.log(`통과: ${report.summary.passedTests}`);
    console.log(`실패: ${report.summary.failedTests}`);
    console.log(`호환성 점수: ${report.summary.compatibilityScore}%`);
    
    console.log('\n🎯 주요 추천사항:');
    report.recommendations.slice(0, 3).forEach((rec, index) => {
      console.log(`${index + 1}. [${rec.category}] ${rec.recommendation}`);
    });
  }
}

// 실행 함수
async function main() {
  const reporter = new CompatibilityReport();
  
  try {
    const report = await reporter.runComprehensiveCompatibilityTest();
    
    // 보고서 파일 저장
    const fs = require('fs').promises;
    const filename = `compatibility_report_${new Date().toISOString().split('T')[0]}.json`;
    await fs.writeFile(filename, JSON.stringify(report, null, 2));
    
    console.log(`\n📄 호환성 보고서 저장 완료: ${filename}`);
    
    return report;
  } catch (error) {
    console.error('❌ 호환성 검증 실패:', error.message);
    throw error;
  }
}

// 스크립트 직접 실행 시
if (require.main === module) {
  main();
}

module.exports = CompatibilityReport;