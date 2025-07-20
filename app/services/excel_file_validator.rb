# frozen_string_literal: true

class ExcelFileValidator
  # 지원하는 모든 Excel 형식
  SUPPORTED_FORMATS = %w[
    .xlsx .xls .xlsb .xlsm
    .xltx .xlt .xltm .ods .csv
  ].freeze

  # MIME 타입 매핑
  MIME_TYPES = {
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
    "application/vnd.ms-excel" => ".xls",
    "application/vnd.ms-excel.sheet.binary.macroEnabled.12" => ".xlsb",
    "application/vnd.ms-excel.sheet.macroEnabled.12" => ".xlsm",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.template" => ".xltx",
    "application/vnd.ms-excel.template" => ".xlt",
    "application/vnd.ms-excel.template.macroEnabled.12" => ".xltm",
    "application/vnd.oasis.opendocument.spreadsheet" => ".ods",
    "text/csv" => ".csv"
  }.freeze

  # 파일 시그니처 검증을 위한 매직 바이트
  FILE_SIGNATURES = {
    ".xlsx" => [ 0x50, 0x4B ], # ZIP signature (XLSX는 ZIP 기반)
    ".xlsm" => [ 0x50, 0x4B ], # ZIP signature
    ".xltx" => [ 0x50, 0x4B ], # ZIP signature
    ".xltm" => [ 0x50, 0x4B ], # ZIP signature
    ".xls" => [ 0xD0, 0xCF ], # OLE signature
    ".xlt" => [ 0xD0, 0xCF ], # OLE signature
    ".xlsb" => [ 0x50, 0x4B ], # ZIP signature
    ".ods" => [ 0x50, 0x4B ]   # ZIP signature (ODS도 ZIP 기반)
  }.freeze

  def self.validate_file(uploaded_file)
    new(uploaded_file).validate
  end

  def initialize(uploaded_file)
    @uploaded_file = uploaded_file
    @original_filename = uploaded_file.original_filename
    @content_type = uploaded_file.content_type
    @file_content = uploaded_file.read(16) # 시그니처 검증용으로 처음 16바이트만 읽기
    uploaded_file.rewind # 파일 포인터 초기화
  end

  def validate
    result = {
      valid: false,
      file_format: nil,
      detected_type: nil,
      errors: []
    }

    # 1. 파일 확장자 검증
    file_extension = File.extname(@original_filename).downcase
    unless SUPPORTED_FORMATS.include?(file_extension)
      result[:errors] << "Unsupported file format: #{file_extension}"
      return result
    end

    # 2. MIME 타입 검증
    if @content_type && !valid_mime_type?(@content_type, file_extension)
      result[:errors] << "MIME type mismatch: #{@content_type} does not match #{file_extension}"
    end

    # 3. 파일 시그니처 검증
    unless valid_file_signature?(file_extension)
      result[:errors] << "Invalid file signature for #{file_extension}"
    end

    # 4. 파일 크기 검증
    if @uploaded_file.size > 50.megabytes
      result[:errors] << "File size exceeds 50MB limit"
    end

    if @uploaded_file.size == 0
      result[:errors] << "File is empty"
    end

    # 결과 설정
    if result[:errors].empty?
      result[:valid] = true
      result[:file_format] = file_extension
      result[:detected_type] = detect_specific_type(file_extension)
    end

    result
  end

  private

  def valid_mime_type?(content_type, file_extension)
    # MIME 타입이 확장자와 일치하는지 확인
    expected_extension = MIME_TYPES[content_type]
    expected_extension == file_extension || content_type == "application/octet-stream"
  end

  def valid_file_signature?(file_extension)
    return true unless FILE_SIGNATURES.key?(file_extension) # CSV나 시그니처가 없는 형식
    return true if @file_content.nil? || @file_content.empty?

    expected_signature = FILE_SIGNATURES[file_extension]
    file_bytes = @file_content.bytes

    expected_signature.each_with_index do |byte, index|
      return false if file_bytes[index] != byte
    end

    true
  end

  def detect_specific_type(file_extension)
    case file_extension
    when ".xlsx", ".xlsm", ".xltx", ".xltm"
      "modern_excel"
    when ".xls", ".xlt"
      "legacy_excel"
    when ".xlsb"
      "binary_excel"
    when ".ods"
      "open_document"
    when ".csv"
      "comma_separated"
    else
      "unknown"
    end
  end
end
