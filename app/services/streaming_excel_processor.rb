# frozen_string_literal: true

# 대용량 Excel 파일을 위한 스트리밍 처리 서비스
# Creek (읽기) 및 Xlsxtream (쓰기)를 사용하여 메모리 효율적인 처리
class StreamingExcelProcessor
  include ActiveModel::Model

  # 청크 크기 설정 (행 단위)
  DEFAULT_CHUNK_SIZE = 1000
  MAX_CHUNK_SIZE = 10000

  # 스트리밍 모드
  STREAMING_MODES = {
    read: :creek,        # 읽기 전용 스트리밍
    write: :xlsxtream,   # 쓰기 전용 스트리밍
    transform: :both     # 읽기 + 변환 + 쓰기
  }.freeze

  attr_reader :file_path, :mode, :chunk_size, :options

  def initialize(file_path: nil, mode: :read, chunk_size: DEFAULT_CHUNK_SIZE, **options)
    @file_path = file_path
    @mode = mode
    @chunk_size = [ chunk_size, MAX_CHUNK_SIZE ].min
    @options = options
    @processed_rows = 0
    @start_time = nil

    validate_configuration
  end

  # === 스트리밍 읽기 ===

  # Creek을 사용한 스트리밍 읽기
  def stream_read(&block)
    unless block_given?
      return Common::Result.failure(
        Common::Errors::ValidationError.new(
          message: "블록이 필요합니다",
          details: { method: "stream_read" }
        )
      )
    end

    @start_time = Time.current

    begin
      Rails.logger.info("스트리밍 Excel 읽기 시작: #{@file_path}")

      creek = Creek::Book.new(@file_path,
        check_file_extension: false,
        with_headers: @options[:with_headers]
      )

      total_sheets = creek.sheets.count
      results = []

      creek.sheets.each_with_index do |sheet, sheet_index|
        sheet_result = process_sheet_streaming(sheet, sheet_index, total_sheets, &block)
        results << sheet_result
      end

      elapsed_time = Time.current - @start_time

      Rails.logger.info("스트리밍 읽기 완료: #{@processed_rows}행 처리 (#{elapsed_time.round(2)}초)")

      Common::Result.success({
        file_path: @file_path,
        sheets_processed: total_sheets,
        total_rows: @processed_rows,
        elapsed_time: elapsed_time,
        rows_per_second: (@processed_rows / elapsed_time).round(2),
        results: results
      })

    rescue StandardError => e
      Rails.logger.error("스트리밍 읽기 실패: #{e.message}")
      Common::Result.failure(
        Common::Errors::FileProcessingError.new(
          message: "스트리밍 읽기 실패: #{e.message}",
          details: { file_path: @file_path, rows_processed: @processed_rows }
        )
      )
    end
  end

  # 청크 단위로 데이터 읽기
  def read_in_chunks
    chunks = []
    current_chunk = []

    stream_read do |row_data, metadata|
      current_chunk << { data: row_data, metadata: metadata }

      if current_chunk.size >= @chunk_size
        chunks << process_chunk(current_chunk)
        current_chunk = []
      end
    end

    # 마지막 청크 처리
    chunks << process_chunk(current_chunk) if current_chunk.any?

    Common::Result.success({
      chunks_count: chunks.count,
      total_rows: @processed_rows,
      chunks: chunks
    })
  end

  # === 스트리밍 쓰기 ===

  # Xlsxtream을 사용한 스트리밍 쓰기
  def stream_write(output_path, &block)
    unless block_given?
      return Common::Result.failure(
        Common::Errors::ValidationError.new(
          message: "데이터 생성 블록이 필요합니다",
          details: { method: "stream_write" }
        )
      )
    end

    @start_time = Time.current
    written_rows = 0

    begin
      Rails.logger.info("스트리밍 Excel 쓰기 시작: #{output_path}")

      Xlsxtream::Workbook.open(output_path, @options) do |workbook|
        # 시트 생성
        worksheet = workbook.add_worksheet(
          name: @options[:sheet_name] || "Sheet1",
          auto_format: @options[:auto_format] != false
        )

        # 헤더 쓰기 (옵션)
        if @options[:headers]
          worksheet << @options[:headers]
          written_rows += 1
        end

        # 데이터 생성 및 쓰기
        block.call do |row_data|
          worksheet << row_data
          written_rows += 1

          # 진행 상황 로깅
          if written_rows % 10000 == 0
            Rails.logger.info("스트리밍 쓰기 진행: #{written_rows}행 작성")
          end
        end
      end

      elapsed_time = Time.current - @start_time

      Rails.logger.info("스트리밍 쓰기 완료: #{written_rows}행 작성 (#{elapsed_time.round(2)}초)")

      Common::Result.success({
        output_path: output_path,
        rows_written: written_rows,
        elapsed_time: elapsed_time,
        rows_per_second: (written_rows / elapsed_time).round(2),
        file_size: File.size(output_path)
      })

    rescue StandardError => e
      Rails.logger.error("스트리밍 쓰기 실패: #{e.message}")
      Common::Result.failure(
        Common::Errors::FileProcessingError.new(
          message: "스트리밍 쓰기 실패: #{e.message}",
          details: { output_path: output_path, rows_written: written_rows }
        )
      )
    end
  end

  # === 변환 및 필터링 ===

  # 스트리밍 변환 (읽기 → 처리 → 쓰기)
  def transform_streaming(output_path, &transform_block)
    unless transform_block
      return Common::Result.failure(
        Common::Errors::ValidationError.new(
          message: "변환 블록이 필요합니다",
          details: { method: "transform_streaming" }
        )
      )
    end

    @start_time = Time.current
    transform_results = []

    # 스트리밍 쓰기 시작
    write_result = stream_write(output_path) do |write_stream|
      # 스트리밍 읽기 및 변환
      read_result = stream_read do |row_data, metadata|
        # 변환 적용
        transformed = transform_block.call(row_data, metadata)

        # nil이 아닌 경우만 쓰기 (필터링 지원)
        if transformed
          write_stream.call(transformed)
          transform_results << {
            original_row: metadata[:row_index],
            transformed: true
          }
        else
          transform_results << {
            original_row: metadata[:row_index],
            transformed: false,
            filtered: true
          }
        end
      end

      return read_result if read_result.failure?
    end

    return write_result if write_result.failure?

    elapsed_time = Time.current - @start_time
    transformed_count = transform_results.count { |r| r[:transformed] }
    filtered_count = transform_results.count { |r| r[:filtered] }

    Common::Result.success({
      input_file: @file_path,
      output_file: output_path,
      total_rows_read: @processed_rows,
      rows_transformed: transformed_count,
      rows_filtered: filtered_count,
      elapsed_time: elapsed_time,
      performance: {
        rows_per_second: (@processed_rows / elapsed_time).round(2),
        mb_per_second: (File.size(@file_path) / 1024.0 / 1024.0 / elapsed_time).round(2)
      }
    })
  end

  # === 분석 및 집계 ===

  # 스트리밍 방식으로 통계 수집
  def collect_statistics
    stats = {
      sheets: [],
      total_rows: 0,
      total_cells: 0,
      non_empty_cells: 0,
      formulas: 0,
      data_types: Hash.new(0),
      memory_peak: 0
    }

    stream_read do |row_data, metadata|
      stats[:total_rows] += 1

      row_data.each do |cell|
        stats[:total_cells] += 1

        if cell && !cell.to_s.strip.empty?
          stats[:non_empty_cells] += 1

          # 데이터 타입 분석
          case cell
          when Numeric
            stats[:data_types][:numeric] += 1
          when Date, Time, DateTime
            stats[:data_types][:datetime] += 1
          when String
            if cell.start_with?("=")
              stats[:formulas] += 1
              stats[:data_types][:formula] += 1
            else
              stats[:data_types][:text] += 1
            end
          else
            stats[:data_types][:other] += 1
          end
        end
      end

      # 메모리 사용량 체크 (샘플링)
      if stats[:total_rows] % 1000 == 0
        current_memory = memory_usage_mb
        stats[:memory_peak] = [ stats[:memory_peak], current_memory ].max
      end
    end

    Common::Result.success(stats)
  end

  # === 유틸리티 메서드 ===

  # 대용량 파일 여부 확인
  def self.large_file?(file_path, threshold_mb: 10)
    File.size(file_path) > threshold_mb * 1024 * 1024
  end

  # 최적 처리 방식 추천
  def self.recommend_processor(file_path)
    file_size_mb = File.size(file_path) / 1024.0 / 1024.0

    if file_size_mb < 5
      { processor: :roo, reason: "작은 파일은 Roo가 더 간편합니다" }
    elsif file_size_mb < 50
      { processor: :fast_excel, reason: "중간 크기 파일은 FastExcel이 빠릅니다" }
    else
      { processor: :streaming, reason: "대용량 파일은 스트리밍이 필요합니다" }
    end
  rescue StandardError => e
    { processor: :unknown, error: e.message }
  end

  private

  def validate_configuration
    if @mode == :read || @mode == :transform
      unless @file_path && File.exist?(@file_path)
        raise ArgumentError, "읽기 모드에서는 유효한 파일 경로가 필요합니다: #{@file_path}"
      end
    end

    unless STREAMING_MODES.key?(@mode)
      raise ArgumentError, "지원하지 않는 모드: #{@mode}"
    end

    if @chunk_size <= 0
      raise ArgumentError, "청크 크기는 양수여야 합니다: #{@chunk_size}"
    end
  end

  def process_sheet_streaming(sheet, sheet_index, total_sheets)
    sheet_start_time = Time.current
    sheet_rows = 0
    sheet_name = sheet.name || "Sheet#{sheet_index + 1}"

    Rails.logger.info("시트 처리 시작 (#{sheet_index + 1}/#{total_sheets}): #{sheet_name}")

    sheet.simple_rows.each_with_index do |row, row_index|
      # 행 데이터 처리
      row_data = row.values || []

      metadata = {
        sheet_index: sheet_index,
        sheet_name: sheet_name,
        row_index: row_index,
        row_number: row_index + 1,
        timestamp: Time.current
      }

      # 블록 실행
      yield(row_data, metadata) if block_given?

      sheet_rows += 1
      @processed_rows += 1

      # 진행 상황 로깅
      if sheet_rows % 10000 == 0
        elapsed = Time.current - sheet_start_time
        rate = (sheet_rows / elapsed).round(2)
        Rails.logger.info("#{sheet_name}: #{sheet_rows}행 처리 (#{rate}행/초)")
      end
    end

    {
      sheet_name: sheet_name,
      rows_processed: sheet_rows,
      elapsed_time: Time.current - sheet_start_time
    }
  end

  def process_chunk(chunk)
    return [] if chunk.empty?

    {
      size: chunk.size,
      data: chunk,
      processed_at: Time.current
    }
  end

  def memory_usage_mb
    # 프로세스 메모리 사용량 (MB)
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  rescue StandardError
    0
  end

  # === 클래스 메서드 ===

  # 파일 스트리밍 읽기 (간편 메서드)
  def self.read(file_path, **options, &block)
    new(file_path: file_path, mode: :read, **options).stream_read(&block)
  end

  # 파일 스트리밍 쓰기 (간편 메서드)
  def self.write(output_path, **options, &block)
    new(mode: :write, **options).stream_write(output_path, &block)
  end

  # 파일 변환 (간편 메서드)
  def self.transform(input_path, output_path, **options, &block)
    new(file_path: input_path, mode: :transform, **options)
      .transform_streaming(output_path, &block)
  end

  # 통계 수집 (간편 메서드)
  def self.analyze(file_path, **options)
    new(file_path: file_path, mode: :read, **options).collect_statistics
  end
end
