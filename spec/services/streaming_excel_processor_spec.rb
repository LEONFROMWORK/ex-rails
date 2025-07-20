# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StreamingExcelProcessor do
  let(:test_file_path) { Rails.root.join('spec/fixtures/files/large_excel.xlsx') }
  let(:output_path) { Rails.root.join('tmp/test_output.xlsx') }

  before do
    # 테스트 파일 생성 (필요한 경우)
    create_test_excel_file(test_file_path) unless File.exist?(test_file_path)
  end

  after do
    # 테스트 출력 파일 정리
    File.delete(output_path) if File.exist?(output_path)
  end

  describe '#initialize' do
    it '유효한 설정으로 초기화된다' do
      processor = described_class.new(
        file_path: test_file_path,
        mode: :read,
        chunk_size: 500
      )

      expect(processor.file_path).to eq(test_file_path)
      expect(processor.mode).to eq(:read)
      expect(processor.chunk_size).to eq(500)
    end

    it '잘못된 모드에서 에러를 발생시킨다' do
      expect {
        described_class.new(file_path: test_file_path, mode: :invalid)
      }.to raise_error(ArgumentError, /지원하지 않는 모드/)
    end

    it '읽기 모드에서 파일이 없으면 에러를 발생시킨다' do
      expect {
        described_class.new(file_path: 'nonexistent.xlsx', mode: :read)
      }.to raise_error(ArgumentError, /유효한 파일 경로가 필요/)
    end
  end

  describe '#stream_read' do
    let(:processor) { described_class.new(file_path: test_file_path, mode: :read) }

    it '블록 없이 호출하면 에러를 반환한다' do
      result = processor.stream_read

      expect(result).to be_failure
      expect(result.error.message).to include('블록이 필요합니다')
    end

    it '파일을 스트리밍으로 읽는다' do
      rows_read = []

      result = processor.stream_read do |row_data, metadata|
        rows_read << {
          data: row_data,
          sheet: metadata[:sheet_name],
          row_number: metadata[:row_number]
        }
      end

      expect(result).to be_success
      expect(result.value[:total_rows]).to be > 0
      expect(result.value[:sheets_processed]).to be > 0
      expect(rows_read).not_to be_empty
    end

    it '메타데이터를 올바르게 제공한다' do
      metadata_samples = []

      processor.stream_read do |_, metadata|
        metadata_samples << metadata if metadata_samples.size < 5
      end

      metadata_samples.each do |metadata|
        expect(metadata).to have_key(:sheet_index)
        expect(metadata).to have_key(:sheet_name)
        expect(metadata).to have_key(:row_index)
        expect(metadata).to have_key(:row_number)
        expect(metadata[:row_number]).to eq(metadata[:row_index] + 1)
      end
    end
  end

  describe '#read_in_chunks' do
    let(:processor) { described_class.new(file_path: test_file_path, mode: :read, chunk_size: 10) }

    it '데이터를 청크 단위로 읽는다' do
      result = processor.read_in_chunks

      expect(result).to be_success
      expect(result.value[:chunks_count]).to be > 0
      expect(result.value[:chunks]).to be_an(Array)

      # 첫 번째 청크 검증
      first_chunk = result.value[:chunks].first
      expect(first_chunk[:size]).to be <= 10
      expect(first_chunk[:data]).to be_an(Array)
    end
  end

  describe '#stream_write' do
    let(:processor) { described_class.new(mode: :write) }

    it '블록 없이 호출하면 에러를 반환한다' do
      result = processor.stream_write(output_path)

      expect(result).to be_failure
      expect(result.error.message).to include('데이터 생성 블록이 필요')
    end

    it '데이터를 스트리밍으로 쓴다' do
      test_data = [
        [ 'Header1', 'Header2', 'Header3' ],
        [ 'Data1', 'Data2', 'Data3' ],
        [ 'Data4', 'Data5', 'Data6' ]
      ]

      result = processor.stream_write(output_path) do |writer|
        test_data.each { |row| writer.call(row) }
      end

      expect(result).to be_success
      expect(result.value[:rows_written]).to eq(3)
      expect(File).to exist(output_path)
      expect(result.value[:file_size]).to be > 0
    end

    it '헤더 옵션을 지원한다' do
      processor = described_class.new(
        mode: :write,
        headers: [ 'Column A', 'Column B', 'Column C' ]
      )

      result = processor.stream_write(output_path) do |writer|
        writer.call([ 1, 2, 3 ])
        writer.call([ 4, 5, 6 ])
      end

      expect(result).to be_success
      expect(result.value[:rows_written]).to eq(3) # 헤더 + 2행
    end
  end

  describe '#transform_streaming' do
    let(:processor) { described_class.new(file_path: test_file_path, mode: :transform) }

    it '블록 없이 호출하면 에러를 반환한다' do
      result = processor.transform_streaming(output_path)

      expect(result).to be_failure
      expect(result.error.message).to include('변환 블록이 필요')
    end

    it '데이터를 변환하여 저장한다' do
      result = processor.transform_streaming(output_path) do |row_data, metadata|
        # 모든 숫자 값을 2배로 변환
        row_data.map { |cell| cell.is_a?(Numeric) ? cell * 2 : cell }
      end

      expect(result).to be_success
      expect(result.value[:rows_transformed]).to be > 0
      expect(File).to exist(output_path)
    end

    it '필터링을 지원한다' do
      result = processor.transform_streaming(output_path) do |row_data, metadata|
        # 첫 번째 열이 비어있지 않은 행만 포함
        row_data.first.to_s.strip.empty? ? nil : row_data
      end

      expect(result).to be_success
      expect(result.value[:rows_filtered]).to be >= 0
      expect(result.value[:rows_transformed]).to be <= result.value[:total_rows_read]
    end
  end

  describe '#collect_statistics' do
    let(:processor) { described_class.new(file_path: test_file_path, mode: :read) }

    it '파일 통계를 수집한다' do
      result = processor.collect_statistics

      expect(result).to be_success

      stats = result.value
      expect(stats[:total_rows]).to be > 0
      expect(stats[:total_cells]).to be > 0
      expect(stats[:non_empty_cells]).to be >= 0
      expect(stats[:data_types]).to be_a(Hash)
      expect(stats[:memory_peak]).to be >= 0
    end

    it '수식을 올바르게 감지한다' do
      # 수식이 포함된 테스트 파일 생성
      create_test_excel_with_formulas(test_file_path)

      result = processor.collect_statistics
      stats = result.value

      expect(stats[:formulas]).to be > 0
      expect(stats[:data_types][:formula]).to eq(stats[:formulas])
    end
  end

  describe '.large_file?' do
    it '파일 크기를 올바르게 판단한다' do
      # 작은 파일
      expect(described_class.large_file?(test_file_path, threshold_mb: 100)).to be false

      # 임계값을 낮춰서 테스트
      expect(described_class.large_file?(test_file_path, threshold_mb: 0.001)).to be true
    end
  end

  describe '.recommend_processor' do
    it '파일 크기에 따라 적절한 프로세서를 추천한다' do
      recommendation = described_class.recommend_processor(test_file_path)

      expect(recommendation).to have_key(:processor)
      expect(recommendation).to have_key(:reason)
      expect([ :roo, :fast_excel, :streaming ]).to include(recommendation[:processor])
    end
  end

  describe '클래스 메서드' do
    it '.read 메서드가 동작한다' do
      row_count = 0

      result = described_class.read(test_file_path) do |_, _|
        row_count += 1
      end

      expect(result).to be_success
      expect(row_count).to be > 0
    end

    it '.write 메서드가 동작한다' do
      result = described_class.write(output_path) do |writer|
        writer.call([ 'Test', 'Data' ])
      end

      expect(result).to be_success
      expect(File).to exist(output_path)
    end

    it '.transform 메서드가 동작한다' do
      result = described_class.transform(test_file_path, output_path) do |row_data, _|
        row_data.map(&:to_s).map(&:upcase)
      end

      expect(result).to be_success
      expect(File).to exist(output_path)
    end

    it '.analyze 메서드가 동작한다' do
      result = described_class.analyze(test_file_path)

      expect(result).to be_success
      expect(result.value).to have_key(:total_rows)
      expect(result.value).to have_key(:data_types)
    end
  end

  private

  def create_test_excel_file(path)
    require 'roo'

    # 디렉토리 생성
    FileUtils.mkdir_p(File.dirname(path))

    # 간단한 Excel 파일 생성 (Roo는 읽기 전용이므로 다른 방법 사용)
    # 실제 구현에서는 write_xlsx 같은 gem을 사용할 수 있음
    # 여기서는 CSV를 Excel로 변환하는 방식을 사용
    CSV.open(path.sub('.xlsx', '.csv'), 'w') do |csv|
      csv << [ 'Name', 'Age', 'City' ]
      csv << [ 'John', 30, 'New York' ]
      csv << [ 'Jane', 25, 'Los Angeles' ]
      csv << [ 'Bob', 35, 'Chicago' ]
    end
  end

  def create_test_excel_with_formulas(path)
    # 수식이 포함된 테스트 파일 생성
    # 실제 구현에서는 rubyXL 또는 write_xlsx를 사용
    CSV.open(path.sub('.xlsx', '.csv'), 'w') do |csv|
      csv << [ 'Value1', 'Value2', 'Formula' ]
      csv << [ 10, 20, '=A2+B2' ]
      csv << [ 30, 40, '=SUM(A2:B3)' ]
      csv << [ 50, 60, '=AVERAGE(A2:B4)' ]
    end
  end
end
