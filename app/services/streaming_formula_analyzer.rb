# frozen_string_literal: true

# 스트리밍 방식으로 대용량 Excel 파일의 수식을 분석하는 서비스
# StreamingExcelProcessor와 FormulaEngineClient를 통합
class StreamingFormulaAnalyzer
  include ActiveModel::Model

  # 배치 크기 설정
  BATCH_SIZE = 100          # FormulaEngine로 전송할 배치 크기
  MAX_BATCH_SIZE = 500      # 최대 배치 크기
  ANALYSIS_CHUNK_SIZE = 1000 # 분석할 행 청크 크기

  attr_reader :options, :results

  def initialize(**options)
    @options = options
    @results = {
      total_rows: 0,
      total_formulas: 0,
      formula_complexity: { simple: 0, medium: 0, complex: 0 },
      functions_used: Hash.new(0),
      errors: [],
      performance: {}
    }
    @formula_engine = FormulaEngineClient.instance
    @current_batch = []
  end

  # 대용량 Excel 파일 스트리밍 분석
  def analyze_large_file(file_path, output_path: nil)
    start_time = Time.current

    # 파일 크기 확인
    file_size_mb = File.size(file_path) / 1024.0 / 1024.0
    Rails.logger.info("대용량 Excel 분석 시작: #{file_path} (#{file_size_mb.round(2)}MB)")

    # FormulaEngine 세션 생성
    session_result = @formula_engine.create_session
    return session_result if session_result.failure?

    begin
      # 스트리밍 프로세서 생성
      processor = StreamingExcelProcessor.new(
        file_path: file_path,
        mode: :read,
        chunk_size: ANALYSIS_CHUNK_SIZE
      )

      # 스트리밍 읽기 및 분석
      read_result = processor.stream_read do |row_data, metadata|
        process_row_formulas(row_data, metadata)

        # 배치가 가득 찼으면 FormulaEngine으로 전송
        if @current_batch.size >= BATCH_SIZE
          flush_batch_to_engine
        end
      end

      return read_result if read_result.failure?

      # 남은 배치 처리
      flush_batch_to_engine if @current_batch.any?

      # 최종 분석 수행
      final_analysis = perform_final_analysis

      # 결과 저장 (옵션)
      save_results(output_path) if output_path

      elapsed_time = Time.current - start_time
      @results[:performance] = {
        total_time: elapsed_time,
        rows_per_second: (@results[:total_rows] / elapsed_time).round(2),
        formulas_per_second: (@results[:total_formulas] / elapsed_time).round(2),
        file_size_mb: file_size_mb,
        mb_per_second: (file_size_mb / elapsed_time).round(2)
      }

      Rails.logger.info("대용량 Excel 분석 완료: #{@results[:total_formulas]}개 수식 발견 (#{elapsed_time.round(2)}초)")

      Common::Result.success(@results)

    ensure
      # 세션 정리
      @formula_engine.destroy_session
    end

  rescue StandardError => e
    Rails.logger.error("스트리밍 수식 분석 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: "스트리밍 분석 실패: #{e.message}",
        code: "STREAMING_ANALYSIS_ERROR"
      )
    )
  end

  # 여러 파일 동시 분석 (병렬 처리)
  def analyze_multiple_files(file_paths, parallel: true)
    start_time = Time.current

    if parallel && file_paths.size > 1
      analyze_files_parallel(file_paths)
    else
      analyze_files_sequential(file_paths)
    end

    elapsed_time = Time.current - start_time

    Common::Result.success({
      files_analyzed: file_paths.size,
      total_time: elapsed_time,
      average_time_per_file: (elapsed_time / file_paths.size).round(2),
      results: @results
    })
  end

  # 수식 복잡도 기반 최적화 분석
  def analyze_for_optimization(file_path)
    optimization_suggestions = []
    formula_patterns = Hash.new(0)

    # 스트리밍 분석으로 패턴 수집
    analyze_result = analyze_large_file(file_path)
    return analyze_result if analyze_result.failure?

    # 최적화 제안 생성
    if @results[:formula_complexity][:complex] > 100
      optimization_suggestions << {
        type: "complex_formulas",
        severity: "high",
        message: "#{@results[:formula_complexity][:complex]}개의 복잡한 수식이 발견되었습니다.",
        recommendation: "복잡한 수식을 여러 셀로 분리하거나 도우미 열을 사용하세요."
      }
    end

    # 자주 사용되는 함수 분석
    top_functions = @results[:functions_used]
      .sort_by { |_, count| -count }
      .first(10)

    volatile_functions = %w[NOW TODAY RAND RANDBETWEEN OFFSET INDIRECT]
    volatile_count = top_functions
      .select { |func, _| volatile_functions.include?(func) }
      .sum { |_, count| count }

    if volatile_count > 50
      optimization_suggestions << {
        type: "volatile_functions",
        severity: "medium",
        message: "#{volatile_count}개의 휘발성 함수 사용이 감지되었습니다.",
        recommendation: "휘발성 함수는 시트가 변경될 때마다 재계산됩니다. 정적 값으로 대체를 고려하세요."
      }
    end

    Common::Result.success({
      analysis: @results,
      optimization_suggestions: optimization_suggestions,
      top_functions: top_functions
    })
  end

  private

  def process_row_formulas(row_data, metadata)
    @results[:total_rows] += 1

    row_data.each_with_index do |cell, col_index|
      next unless cell.is_a?(String) && cell.start_with?("=")

      @results[:total_formulas] += 1

      # 수식 정보 수집
      formula_info = {
        formula: cell,
        location: {
          sheet: metadata[:sheet_name],
          row: metadata[:row_number],
          column: col_index + 1
        }
      }

      # 복잡도 분석
      complexity = analyze_formula_complexity(cell)
      @results[:formula_complexity][complexity] += 1

      # 함수 추출
      functions = extract_functions(cell)
      functions.each { |func| @results[:functions_used][func] += 1 }

      # 배치에 추가
      @current_batch << formula_info
    end
  end

  def flush_batch_to_engine
    return if @current_batch.empty?

    begin
      # 배치 데이터를 FormulaEngine 형식으로 변환
      batch_data = @current_batch.map do |info|
        [ info[:location][:row] - 1, info[:location][:column] - 1, info[:formula] ]
      end

      # FormulaEngine로 전송
      load_result = @formula_engine.load_excel_data({
        sheets: {
          @current_batch.first[:location][:sheet] => batch_data
        }
      })

      if load_result.failure?
        Rails.logger.warn("배치 로드 실패: #{load_result.error}")
        @results[:errors] << {
          type: "batch_load_error",
          batch_size: @current_batch.size,
          error: load_result.error
        }
      end

    rescue StandardError => e
      Rails.logger.error("배치 처리 중 오류: #{e.message}")
      @results[:errors] << {
        type: "batch_processing_error",
        batch_size: @current_batch.size,
        error: e.message
      }
    ensure
      @current_batch.clear
    end
  end

  def analyze_formula_complexity(formula)
    # 수식 복잡도 분석
    function_count = formula.scan(/[A-Z]+\s*\(/).size
    nesting_level = calculate_nesting_level(formula)
    formula_length = formula.length

    if function_count > 5 || nesting_level > 3 || formula_length > 200
      :complex
    elsif function_count > 2 || nesting_level > 1 || formula_length > 100
      :medium
    else
      :simple
    end
  end

  def calculate_nesting_level(formula)
    max_level = 0
    current_level = 0

    formula.each_char do |char|
      case char
      when "("
        current_level += 1
        max_level = [ max_level, current_level ].max
      when ")"
        current_level -= 1
      end
    end

    max_level
  end

  def extract_functions(formula)
    formula.scan(/([A-Z][A-Z0-9]*)\s*\(/).flatten.uniq
  end

  def perform_final_analysis
    # FormulaEngine에서 최종 분석 수행
    analysis_result = @formula_engine.analyze_formulas

    if analysis_result.success?
      # 결과 병합
      engine_analysis = analysis_result.value[:analysis]

      if engine_analysis
        @results[:circular_references] = engine_analysis[:circularReferences] || []
        @results[:error_cells] = engine_analysis[:errors] || []
        @results[:dependencies] = engine_analysis[:dependencies] || []
      end
    end

    analysis_result
  end

  def save_results(output_path)
    # 분석 결과를 Excel 파일로 저장
    StreamingExcelProcessor.write(output_path,
      sheet_name: "수식 분석 결과",
      headers: [ "항목", "값", "설명" ]
    ) do |writer|
      # 요약 정보
      writer.call([ "총 행 수", @results[:total_rows], "분석된 전체 행 수" ])
      writer.call([ "총 수식 수", @results[:total_formulas], "발견된 수식의 총 개수" ])
      writer.call([ "" ])

      # 복잡도 분석
      writer.call([ "수식 복잡도", "", "" ])
      @results[:formula_complexity].each do |level, count|
        writer.call([ "  #{level}", count, "#{level} 복잡도 수식 개수" ])
      end
      writer.call([ "" ])

      # 상위 함수
      writer.call([ "자주 사용된 함수 Top 10", "", "" ])
      @results[:functions_used]
        .sort_by { |_, count| -count }
        .first(10)
        .each do |func, count|
          writer.call([ "  #{func}", count, "#{func} 함수 사용 횟수" ])
        end
      writer.call([ "" ])

      # 성능 지표
      writer.call([ "성능 지표", "", "" ])
      @results[:performance].each do |metric, value|
        writer.call([ "  #{metric}", value, "" ])
      end

      # 오류 정보
      if @results[:errors].any?
        writer.call([ "" ])
        writer.call([ "오류", "", "" ])
        @results[:errors].each_with_index do |error, idx|
          writer.call([ "  오류 #{idx + 1}", error[:type], error[:error] ])
        end
      end
    end

    Rails.logger.info("분석 결과 저장 완료: #{output_path}")
  rescue StandardError => e
    Rails.logger.error("결과 저장 실패: #{e.message}")
  end

  def analyze_files_parallel(file_paths)
    require "parallel"

    # 병렬 처리 (프로세스 수는 CPU 코어 수에 따라 조정)
    parallel_results = Parallel.map(file_paths, in_processes: 4) do |file_path|
      analyzer = self.class.new(**@options)
      analyzer.analyze_large_file(file_path)
    end

    # 결과 병합
    merge_parallel_results(parallel_results)
  end

  def analyze_files_sequential(file_paths)
    file_paths.each do |file_path|
      analyze_large_file(file_path)
    end
  end

  def merge_parallel_results(parallel_results)
    parallel_results.each do |result|
      next unless result.success?

      data = result.value
      @results[:total_rows] += data[:total_rows]
      @results[:total_formulas] += data[:total_formulas]

      # 복잡도 병합
      data[:formula_complexity].each do |level, count|
        @results[:formula_complexity][level] += count
      end

      # 함수 사용 병합
      data[:functions_used].each do |func, count|
        @results[:functions_used][func] += count
      end

      # 오류 병합
      @results[:errors].concat(data[:errors])
    end
  end

  # === 클래스 메서드 ===

  # 대용량 파일 분석 (간편 메서드)
  def self.analyze(file_path, **options)
    new(**options).analyze_large_file(file_path)
  end

  # 최적화 분석 (간편 메서드)
  def self.analyze_for_optimization(file_path, **options)
    new(**options).analyze_for_optimization(file_path)
  end

  # 여러 파일 분석 (간편 메서드)
  def self.analyze_multiple(file_paths, **options)
    new(**options).analyze_multiple_files(file_paths)
  end
end
