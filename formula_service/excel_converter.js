const ExcelJS = require('exceljs');
const { HyperFormula } = require('hyperformula');

/**
 * ExcelJS와 HyperFormula 간의 데이터 변환 유틸리티
 * HyperFormula와 ExcelJS 라이브러리 간의 상호운용성을 제공
 */
class ExcelConverter {
  constructor() {
    this.workbook = null;
    this.hyperFormula = null;
  }

  /**
   * ExcelJS 워크북을 HyperFormula 데이터 형식으로 변환
   * @param {ExcelJS.Workbook} workbook - ExcelJS 워크북 객체
   * @returns {Object} HyperFormula에서 사용할 수 있는 시트 데이터
   */
  excelToHyperFormula(workbook) {
    const sheets = {};
    const metadata = {
      workbookName: workbook.title || 'Untitled',
      totalSheets: workbook.worksheets.length,
      convertedAt: new Date().toISOString(),
      warnings: []
    };

    workbook.worksheets.forEach((worksheet, index) => {
      try {
        const sheetData = this.convertWorksheet(worksheet);
        sheets[worksheet.name || `Sheet${index + 1}`] = sheetData.values;
        
        // 메타데이터 수집
        metadata[worksheet.name] = {
          dimensions: sheetData.dimensions,
          formulaCount: sheetData.formulaCount,
          cellCount: sheetData.cellCount,
          hasProtection: !!worksheet.protection
        };
      } catch (error) {
        metadata.warnings.push({
          sheet: worksheet.name,
          error: error.message,
          type: 'sheet_conversion_error'
        });
      }
    });

    return { sheets, metadata };
  }

  /**
   * 개별 워크시트를 HyperFormula 형식으로 변환
   * @param {ExcelJS.Worksheet} worksheet - ExcelJS 워크시트
   * @returns {Object} 변환된 시트 데이터
   */
  convertWorksheet(worksheet) {
    const values = [];
    let maxRow = 0;
    let maxCol = 0;
    let formulaCount = 0;
    let cellCount = 0;

    // 워크시트의 실제 사용 범위 계산
    worksheet.eachRow({ includeEmpty: false }, (row, rowNumber) => {
      maxRow = Math.max(maxRow, rowNumber);
      
      row.eachCell({ includeEmpty: false }, (cell, colNumber) => {
        maxCol = Math.max(maxCol, colNumber);
        cellCount++;
        
        if (cell.formula) {
          formulaCount++;
        }
      });
    });

    // 2D 배열 초기화
    for (let r = 0; r < maxRow; r++) {
      values[r] = new Array(maxCol).fill(null);
    }

    // 셀 데이터 변환
    worksheet.eachRow({ includeEmpty: false }, (row, rowNumber) => {
      row.eachCell({ includeEmpty: false }, (cell, colNumber) => {
        const convertedValue = this.convertCellValue(cell);
        values[rowNumber - 1][colNumber - 1] = convertedValue;
      });
    });

    return {
      values,
      dimensions: { width: maxCol, height: maxRow },
      formulaCount,
      cellCount
    };
  }

  /**
   * ExcelJS 셀 값을 HyperFormula 형식으로 변환
   * @param {ExcelJS.Cell} cell - ExcelJS 셀 객체
   * @returns {*} HyperFormula에서 사용할 수 있는 값
   */
  convertCellValue(cell) {
    // 수식이 있는 경우
    if (cell.formula) {
      return this.normalizeFormula(cell.formula);
    }

    // 값 타입별 처리
    switch (cell.type) {
      case ExcelJS.ValueType.Number:
        return cell.value;
      
      case ExcelJS.ValueType.String:
      case ExcelJS.ValueType.RichText:
        return typeof cell.value === 'string' ? cell.value : cell.text || '';
      
      case ExcelJS.ValueType.Date:
        return cell.value instanceof Date ? cell.value : new Date(cell.value);
      
      case ExcelJS.ValueType.Boolean:
        return Boolean(cell.value);
      
      case ExcelJS.ValueType.Error:
        return `#${cell.value.error || 'ERROR'}`;
      
      case ExcelJS.ValueType.Null:
      case ExcelJS.ValueType.Formula:
      default:
        return cell.value;
    }
  }

  /**
   * HyperFormula 데이터를 ExcelJS 워크북으로 변환
   * @param {Object} hyperFormulaData - HyperFormula 시트 데이터
   * @param {Object} metadata - 추가 메타데이터
   * @returns {ExcelJS.Workbook} ExcelJS 워크북 객체
   */
  hyperFormulaToExcel(hyperFormulaData, metadata = {}) {
    const workbook = new ExcelJS.Workbook();
    
    // 워크북 메타데이터 설정
    workbook.title = metadata.title || 'HyperFormula Export';
    workbook.creator = metadata.creator || 'FormulaEngine Service';
    workbook.created = new Date();
    workbook.modified = new Date();

    // 각 시트 변환
    Object.entries(hyperFormulaData.sheets || hyperFormulaData).forEach(([sheetName, sheetData]) => {
      try {
        const worksheet = workbook.addWorksheet(sheetName);
        this.populateWorksheet(worksheet, sheetData, metadata[sheetName]);
      } catch (error) {
        console.error(`시트 변환 오류 [${sheetName}]:`, error.message);
      }
    });

    return workbook;
  }

  /**
   * HyperFormula 시트 데이터로 ExcelJS 워크시트 채우기
   * @param {ExcelJS.Worksheet} worksheet - ExcelJS 워크시트
   * @param {Array} sheetData - HyperFormula 시트 데이터 (2D 배열)
   * @param {Object} sheetMetadata - 시트 메타데이터
   */
  populateWorksheet(worksheet, sheetData, sheetMetadata = {}) {
    if (!Array.isArray(sheetData) || sheetData.length === 0) {
      return;
    }

    // 데이터 행별 처리
    sheetData.forEach((row, rowIndex) => {
      if (!Array.isArray(row)) return;
      
      const excelRow = worksheet.getRow(rowIndex + 1);
      
      row.forEach((cellValue, colIndex) => {
        if (cellValue !== null && cellValue !== undefined) {
          const cell = excelRow.getCell(colIndex + 1);
          this.setCellValue(cell, cellValue);
        }
      });
      
      excelRow.commit();
    });

    // 시트 스타일링 적용 (선택사항)
    if (sheetMetadata.autoFilter) {
      worksheet.autoFilter = sheetMetadata.autoFilter;
    }
    
    if (sheetMetadata.columnWidths) {
      sheetMetadata.columnWidths.forEach((width, index) => {
        worksheet.getColumn(index + 1).width = width;
      });
    }
  }

  /**
   * ExcelJS 셀에 값 설정 (타입별 처리)
   * @param {ExcelJS.Cell} cell - ExcelJS 셀 객체
   * @param {*} value - 설정할 값
   */
  setCellValue(cell, value) {
    if (value === null || value === undefined) {
      return;
    }

    // 수식인지 확인
    if (typeof value === 'string' && value.startsWith('=')) {
      cell.value = { formula: value.substring(1) };
      return;
    }

    // 에러 값 처리
    if (typeof value === 'string' && value.startsWith('#')) {
      cell.value = { error: value.substring(1) };
      return;
    }

    // 일반 값 설정
    cell.value = value;
  }

  /**
   * 수식 정규화 (ExcelJS -> HyperFormula)
   * @param {string} formula - 원본 수식
   * @returns {string} 정규화된 수식
   */
  normalizeFormula(formula) {
    if (!formula) return formula;
    
    // ExcelJS에서 온 수식은 이미 = 없이 저장됨
    let normalizedFormula = formula.toString();
    
    // HyperFormula 형식으로 변환하기 위해 = 접두사 추가
    if (!normalizedFormula.startsWith('=')) {
      normalizedFormula = '=' + normalizedFormula;
    }
    
    return normalizedFormula;
  }

  /**
   * Excel 파일을 읽어서 HyperFormula 데이터로 변환
   * @param {Buffer|string} file - Excel 파일 데이터 또는 경로
   * @returns {Promise<Object>} 변환된 데이터
   */
  async readExcelFile(file) {
    const workbook = new ExcelJS.Workbook();
    
    try {
      if (Buffer.isBuffer(file)) {
        await workbook.xlsx.load(file);
      } else if (typeof file === 'string') {
        await workbook.xlsx.readFile(file);
      } else {
        throw new Error('지원하지 않는 파일 형식입니다.');
      }
      
      return this.excelToHyperFormula(workbook);
    } catch (error) {
      throw new Error(`Excel 파일 읽기 실패: ${error.message}`);
    }
  }

  /**
   * HyperFormula 데이터를 Excel 파일로 저장
   * @param {Object} data - HyperFormula 데이터
   * @param {string} filepath - 저장할 파일 경로
   * @param {Object} options - 저장 옵션
   * @returns {Promise<Buffer>} Excel 파일 버퍼
   */
  async writeExcelFile(data, filepath = null, options = {}) {
    const workbook = this.hyperFormulaToExcel(data, options.metadata);
    
    if (filepath) {
      await workbook.xlsx.writeFile(filepath);
      return filepath;
    } else {
      return await workbook.xlsx.writeBuffer();
    }
  }

  /**
   * 데이터 호환성 검증
   * @param {Object} originalData - 원본 데이터
   * @param {Object} convertedData - 변환된 데이터
   * @returns {Object} 검증 결과
   */
  validateDataIntegrity(originalData, convertedData) {
    const report = {
      isValid: true,
      errors: [],
      warnings: [],
      statistics: {
        totalSheets: 0,
        totalCells: 0,
        totalFormulas: 0,
        matchingCells: 0,
        mismatchedCells: 0
      }
    };

    try {
      // 기본 구조 검증
      if (!originalData.sheets || !convertedData.sheets) {
        report.isValid = false;
        report.errors.push('시트 데이터가 없습니다.');
        return report;
      }

      // 시트별 비교
      Object.keys(originalData.sheets).forEach(sheetName => {
        if (!convertedData.sheets[sheetName]) {
          report.warnings.push(`시트 '${sheetName}'이 변환 결과에 없습니다.`);
          return;
        }

        const original = originalData.sheets[sheetName];
        const converted = convertedData.sheets[sheetName];
        
        report.statistics.totalSheets++;
        
        // 셀별 비교 (샘플링)
        this.compareSheetData(original, converted, report, sheetName);
      });

      // 최종 검증 상태 결정
      if (report.statistics.mismatchedCells > report.statistics.totalCells * 0.1) {
        report.isValid = false;
        report.errors.push('변환 후 데이터 불일치가 임계값을 초과했습니다.');
      }

    } catch (error) {
      report.isValid = false;
      report.errors.push(`데이터 검증 중 오류: ${error.message}`);
    }

    return report;
  }

  /**
   * 시트 데이터 비교
   * @param {Array} original - 원본 시트 데이터
   * @param {Array} converted - 변환된 시트 데이터
   * @param {Object} report - 검증 보고서
   * @param {string} sheetName - 시트명
   */
  compareSheetData(original, converted, report, sheetName) {
    const maxRows = Math.min(original.length, converted.length, 100); // 최대 100행까지만 비교
    
    for (let r = 0; r < maxRows; r++) {
      const originalRow = original[r] || [];
      const convertedRow = converted[r] || [];
      const maxCols = Math.min(originalRow.length, convertedRow.length, 50); // 최대 50열까지만 비교
      
      for (let c = 0; c < maxCols; c++) {
        report.statistics.totalCells++;
        
        const originalValue = originalRow[c];
        const convertedValue = convertedRow[c];
        
        if (this.valuesMatch(originalValue, convertedValue)) {
          report.statistics.matchingCells++;
        } else {
          report.statistics.mismatchedCells++;
          
          if (report.statistics.mismatchedCells <= 5) { // 최대 5개까지만 로깅
            report.warnings.push(
              `셀 불일치 [${sheetName}!${r+1}:${c+1}]: '${originalValue}' → '${convertedValue}'`
            );
          }
        }
      }
    }
  }

  /**
   * 두 값이 일치하는지 확인
   * @param {*} value1 - 첫 번째 값
   * @param {*} value2 - 두 번째 값
   * @returns {boolean} 일치 여부
   */
  valuesMatch(value1, value2) {
    // null/undefined 처리
    if (value1 == null && value2 == null) return true;
    if (value1 == null || value2 == null) return false;
    
    // 타입이 다른 경우
    if (typeof value1 !== typeof value2) {
      // 숫자와 문자열 숫자는 같은 것으로 간주
      if (typeof value1 === 'number' && typeof value2 === 'string') {
        return value1.toString() === value2;
      }
      if (typeof value1 === 'string' && typeof value2 === 'number') {
        return value1 === value2.toString();
      }
      return false;
    }
    
    // 수식 비교 (= 접두사 무시)
    if (typeof value1 === 'string' && typeof value2 === 'string') {
      const formula1 = value1.startsWith('=') ? value1.substring(1) : value1;
      const formula2 = value2.startsWith('=') ? value2.substring(1) : value2;
      return formula1 === formula2;
    }
    
    return value1 === value2;
  }

  /**
   * 변환 성능 측정
   * @param {Function} conversionFn - 변환 함수
   * @param {*} data - 변환할 데이터
   * @returns {Promise<Object>} 성능 측정 결과
   */
  async measurePerformance(conversionFn, data) {
    const startTime = Date.now();
    const startMemory = process.memoryUsage();
    
    try {
      const result = await conversionFn(data);
      const endTime = Date.now();
      const endMemory = process.memoryUsage();
      
      return {
        success: true,
        result,
        performance: {
          executionTime: endTime - startTime,
          memoryDelta: {
            rss: endMemory.rss - startMemory.rss,
            heapUsed: endMemory.heapUsed - startMemory.heapUsed,
            heapTotal: endMemory.heapTotal - startMemory.heapTotal
          }
        }
      };
    } catch (error) {
      return {
        success: false,
        error: error.message,
        performance: {
          executionTime: Date.now() - startTime,
          failed: true
        }
      };
    }
  }
}

module.exports = ExcelConverter;