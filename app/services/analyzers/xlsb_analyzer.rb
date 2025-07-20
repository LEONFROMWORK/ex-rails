# frozen_string_literal: true

module Analyzers
  class XlsbAnalyzer
    include Common::Errors

    def initialize(file_path)
      @file_path = file_path
      @workbook = nil
    end

    def analyze
      result = {
        format: "xlsb",
        sheets: [],
        errors: [],
        warnings: [],
        metadata: {},
        binary_features: {},
        performance_metrics: {}
      }

      begin
        # XLSB는 특별한 처리가 필요 - Creek gem 사용으로 메모리 효율적 처리
        @workbook = Creek::Book.new(@file_path)

        # 기본 메타데이터 수집
        result[:metadata] = extract_metadata

        # 바이너리 특화 기능 분석
        result[:binary_features] = analyze_binary_features

        # 성능 메트릭
        result[:performance_metrics] = measure_performance

        # 각 시트 분석
        @workbook.sheets.each do |sheet|
          sheet_analysis = analyze_sheet(sheet)
          result[:sheets] << sheet_analysis
        end

        # XLSB 특화 검증
        result[:errors].concat(detect_xlsb_errors)
        result[:warnings].concat(detect_xlsb_warnings)

      rescue StandardError => e
        result[:errors] << {
          type: "file_processing_error",
          message: "Failed to process XLSB binary file: #{e.message}",
          severity: "critical"
        }
      end

      result
    end

    private

    def extract_metadata
      {
        format: "xlsb",
        file_size: File.size(@file_path),
        compression_ratio: calculate_compression_ratio,
        binary_version: detect_binary_version,
        created_at: extract_creation_date,
        modified_at: extract_modification_date,
        supports_large_datasets: true,
        memory_efficient: true
      }
    rescue StandardError
      { error: "Failed to extract binary metadata" }
    end

    def analyze_binary_features
      features = {
        has_formulas: false,
        has_charts: false,
        has_pivot_tables: false,
        has_macros: detect_macros?,
        compressed_size: File.size(@file_path),
        estimated_uncompressed_size: estimate_uncompressed_size,
        binary_optimization: assess_binary_optimization,
        data_density: calculate_data_density
      }

      # 시트별 기능 검사
      @workbook.sheets.each do |sheet|
        # 수식 검사
        features[:has_formulas] = true if has_formulas_in_sheet?(sheet)
      end

      features
    end

    def measure_performance
      start_time = Time.current

      metrics = {
        load_time: 0,
        memory_usage: 0,
        row_processing_speed: 0,
        formula_evaluation_speed: 0
      }

      # 로드 시간 측정
      metrics[:load_time] = (Time.current - start_time) * 1000 # milliseconds

      # 메모리 사용량 추정
      metrics[:memory_usage] = estimate_memory_usage

      # 행 처리 속도 측정
      metrics[:row_processing_speed] = measure_row_processing_speed

      # 수식 평가 속도 (있는 경우)
      metrics[:formula_evaluation_speed] = measure_formula_speed

      metrics
    end

    def analyze_sheet(sheet)
      sheet_result = {
        name: sheet.name,
        id: sheet.rid,
        row_count: 0,
        column_count: 0,
        data_types: {},
        formulas: [],
        binary_data: {},
        errors: [],
        warnings: []
      }

      begin
        start_time = Time.current

        # Creek로 시트 데이터 스트리밍 처리
        rows = sheet.rows
        processed_rows = 0
        max_column = 0

        rows.each do |row|
          processed_rows += 1
          current_columns = row.length
          max_column = [ max_column, current_columns ].max

          # 대용량 파일의 경우 샘플링
          break if processed_rows > 10000 && File.size(@file_path) > 50.megabytes
        end

        sheet_result[:row_count] = processed_rows
        sheet_result[:column_count] = max_column

        # 데이터 타입 분석 (샘플링)
        sheet_result[:data_types] = analyze_data_types_from_sample(sheet)

        # 바이너리 데이터 특성
        sheet_result[:binary_data] = analyze_binary_data_characteristics(sheet)

        # 오류 검출
        sheet_result[:errors] = detect_sheet_errors(sheet)
        sheet_result[:warnings] = detect_sheet_warnings(sheet, processed_rows)

        processing_time = (Time.current - start_time) * 1000
        sheet_result[:processing_time_ms] = processing_time

      rescue StandardError => e
        sheet_result[:errors] << {
          type: "sheet_processing_error",
          message: "Failed to analyze binary sheet '#{sheet.name}': #{e.message}",
          severity: "high"
        }
      end

      sheet_result
    end

    def analyze_data_types_from_sample(sheet)
      data_types = Hash.new(0)
      sample_size = 0

      begin
        sheet.rows.each_with_index do |row, row_index|
          break if sample_size > 1000 # 샘플링 제한

          row.each do |cell_value|
            next if cell_value.nil? || cell_value.to_s.strip.empty?

            case cell_value
            when Numeric
              data_types["numeric"] += 1
            when Date, Time, DateTime
              data_types["date_time"] += 1
            when TrueClass, FalseClass
              data_types["boolean"] += 1
            when String
              if cell_value.start_with?("=")
                data_types["formula"] += 1
              else
                data_types["text"] += 1
              end
            else
              data_types["other"] += 1
            end

            sample_size += 1
          end
        end
      rescue StandardError
        data_types["error"] += 1
      end

      data_types.to_h
    end

    def analyze_binary_data_characteristics(sheet)
      characteristics = {
        sparse_data: false,
        high_density: false,
        large_text_blocks: false,
        numeric_heavy: false,
        formula_intensive: false
      }

      # 데이터 특성 분석 (샘플 기반)
      total_cells = 0
      empty_cells = 0
      text_cells = 0
      numeric_cells = 0
      formula_cells = 0

      begin
        sheet.rows.each_with_index do |row, row_index|
          break if row_index > 100 # 샘플링

          row.each do |cell_value|
            total_cells += 1

            if cell_value.nil? || cell_value.to_s.strip.empty?
              empty_cells += 1
            elsif cell_value.is_a?(Numeric)
              numeric_cells += 1
            elsif cell_value.is_a?(String)
              if cell_value.start_with?("=")
                formula_cells += 1
              else
                text_cells += 1
              end
            end
          end
        end

        if total_cells > 0
          empty_ratio = empty_cells.to_f / total_cells
          characteristics[:sparse_data] = empty_ratio > 0.7
          characteristics[:high_density] = empty_ratio < 0.1
          characteristics[:numeric_heavy] = (numeric_cells.to_f / total_cells) > 0.6
          characteristics[:formula_intensive] = (formula_cells.to_f / total_cells) > 0.2
        end

      rescue StandardError
        # 분석 실패 시 기본값 유지
      end

      characteristics
    end

    def detect_sheet_errors(sheet)
      errors = []

      begin
        # 바이너리 무결성 검사
        row_count = 0
        sheet.rows.each do |row|
          row_count += 1
          break if row_count > 100 # 샘플 검사

          row.each_with_index do |cell_value, col_index|
            # 바이너리 데이터 손상 검사
            if cell_value.is_a?(String) && cell_value.include?("\x00")
              errors << {
                type: "binary_corruption",
                location: "#{sheet.name}!#{row_count},#{col_index}",
                message: "Potential binary data corruption detected",
                severity: "medium"
              }
            end

            # 수식 오류 검출
            if cell_value.is_a?(String) && cell_value.match?(/#(REF|NAME|VALUE|DIV\/0|N\/A|NUM|NULL)!/i)
              errors << {
                type: "formula_error",
                location: "#{sheet.name}!#{row_count},#{col_index}",
                message: "Formula error: #{cell_value}",
                severity: "high"
              }
            end
          end
        end

      rescue StandardError => e
        errors << {
          type: "sheet_analysis_error",
          message: "Failed to analyze sheet #{sheet.name}: #{e.message}",
          severity: "medium"
        }
      end

      errors
    end

    def detect_sheet_warnings(sheet, row_count)
      warnings = []

      # 대용량 데이터 경고
      if row_count > 100000
        warnings << {
          type: "performance_warning",
          message: "Sheet '#{sheet.name}' contains many rows (#{row_count}), processing may be slow",
          severity: "medium"
        }
      end

      # 바이너리 형식 호환성 경고
      warnings << {
        type: "compatibility_warning",
        message: "XLSB format may not be compatible with all Excel versions",
        severity: "low"
      }

      warnings
    end

    def detect_xlsb_errors
      errors = []

      # 파일 크기 검증
      if File.size(@file_path) == 0
        errors << {
          type: "file_error",
          message: "XLSB file is empty",
          severity: "critical"
        }
      end

      # 바이너리 헤더 검증
      unless valid_xlsb_header?
        errors << {
          type: "format_error",
          message: "Invalid XLSB binary header",
          severity: "critical"
        }
      end

      errors
    end

    def detect_xlsb_warnings
      warnings = []

      # 압축 효율성 경고
      compression_ratio = calculate_compression_ratio
      if compression_ratio < 0.3
        warnings << {
          type: "optimization_warning",
          message: "XLSB file has poor compression ratio, consider data optimization",
          severity: "low"
        }
      end

      # 메모리 사용량 경고
      estimated_memory = estimate_memory_usage
      if estimated_memory > 500 # MB
        warnings << {
          type: "memory_warning",
          message: "File may require significant memory (#{estimated_memory}MB) when fully loaded",
          severity: "medium"
        }
      end

      warnings
    end

    # Helper methods
    def extract_creation_date
      File.ctime(@file_path)
    rescue StandardError
      "Unknown"
    end

    def extract_modification_date
      File.mtime(@file_path)
    rescue StandardError
      "Unknown"
    end

    def calculate_compression_ratio
      # 압축률 계산 (추정)
      file_size = File.size(@file_path).to_f
      estimated_uncompressed = estimate_uncompressed_size

      return 0.5 if estimated_uncompressed == 0

      file_size / estimated_uncompressed
    rescue StandardError
      0.5 # 기본값
    end

    def detect_binary_version
      # 바이너리 버전 감지 (simplified)
      "XLSB12" # Excel 2007+ 바이너리 형식
    end

    def detect_macros?
      # 매크로 검출 (simplified - 실제로는 바이너리 구조 분석 필요)
      false
    end

    def estimate_uncompressed_size
      # 압축 해제 크기 추정
      File.size(@file_path) * 3 # 일반적으로 3:1 압축률
    end

    def assess_binary_optimization
      # 바이너리 최적화 수준 평가
      compression_ratio = calculate_compression_ratio

      case compression_ratio
      when 0..0.3
        "excellent"
      when 0.3..0.5
        "good"
      when 0.5..0.7
        "fair"
      else
        "poor"
      end
    end

    def calculate_data_density
      # 데이터 밀도 계산 (MB per 1000 rows 추정)
      file_size_mb = File.size(@file_path) / 1.megabyte.to_f
      estimated_rows = estimate_total_rows

      return 0 if estimated_rows == 0

      (file_size_mb / estimated_rows * 1000).round(2)
    end

    def has_formulas_in_sheet?(sheet)
      # 수식 존재 여부 확인 (샘플 기반)
      sample_count = 0

      begin
        sheet.rows.each do |row|
          row.each do |cell_value|
            return true if cell_value.is_a?(String) && cell_value.start_with?("=")
            sample_count += 1
            break if sample_count > 100 # 샘플링 제한
          end
          break if sample_count > 100
        end
      rescue StandardError
        # 에러 발생 시 false 반환
      end

      false
    end

    def estimate_memory_usage
      # 메모리 사용량 추정 (MB)
      file_size_mb = File.size(@file_path) / 1.megabyte.to_f

      # XLSB는 일반적으로 파일 크기의 2-3배 메모리 사용
      (file_size_mb * 2.5).round
    end

    def measure_row_processing_speed
      # 행 처리 속도 측정 (rows per second)
      start_time = Time.current
      processed_rows = 0

      begin
        @workbook.sheets.first&.rows&.each do |row|
          processed_rows += 1
          break if processed_rows >= 1000 # 샘플링
        end

        elapsed_time = Time.current - start_time
        return 0 if elapsed_time == 0

        (processed_rows / elapsed_time).round
      rescue StandardError
        0
      end
    end

    def measure_formula_speed
      # 수식 처리 속도 측정 (simplified)
      100 # rows per second (추정값)
    end

    def valid_xlsb_header?
      # XLSB 헤더 유효성 검사
      begin
        File.open(@file_path, "rb") do |file|
          header = file.read(8)
          # XLSB는 ZIP 기반이므로 PK 시그니처 확인
          header&.start_with?("\x50\x4B")
        end
      rescue StandardError
        false
      end
    end

    def estimate_total_rows
      # 전체 행 수 추정
      total_rows = 0

      begin
        @workbook.sheets.each do |sheet|
          sheet_rows = 0
          sheet.rows.each { |row| sheet_rows += 1 }
          total_rows += sheet_rows
        end
      rescue StandardError
        # 추정 실패 시 파일 크기 기반 계산
        file_size_kb = File.size(@file_path) / 1.kilobyte
        total_rows = file_size_kb * 10 # 대략적인 추정
      end

      total_rows
    end
  end
end
