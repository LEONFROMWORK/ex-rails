# frozen_string_literal: true

module DataPipeline
  module Jobs
    class OppaduCollectionJob < ApplicationJob
    queue_as :data_collection

    def perform(pipeline_controller:, source:)
      @pipeline_controller = pipeline_controller
      @source = source
      @collected_items = 0

      Rails.logger.info("Starting Oppadu data collection")

      begin
        collect_oppadu_data
        @pipeline_controller.on_collection_success(@source, @collected_items)
      rescue => e
        @pipeline_controller.on_collection_failure(@source, e)
        raise
      end
    end

    private

    def collect_oppadu_data
      # Configuration for Oppadu collection
      config = {
        data_sources: [
          "/Users/kevin/bigdata/data/output/latest_oppadu_data.jsonl",
          "/Users/kevin/bigdata/data/output/oppadu_tutorials.jsonl",
          "/Users/kevin/bigdata/data/output/oppadu_tips.jsonl"
        ],
        batch_size: 100,
        max_lines_per_file: 1000
      }

      config[:data_sources].each do |data_file|
        collect_file_data(data_file, config)
      end
    end

    def collect_file_data(data_file, config)
      unless File.exist?(data_file)
        Rails.logger.warn("Oppadu data file not found: #{data_file}")
        return
      end

      Rails.logger.info("Collecting Oppadu data from: #{data_file}")

      line_count = 0
      batch_data = []

      File.foreach(data_file) do |line|
        line_count += 1

        # Skip empty lines
        next if line.strip.empty?

        # Stop if we've reached the max lines limit
        break if line_count > config[:max_lines_per_file]

        begin
          data = JSON.parse(line)
          batch_data << data

          # Process batch when it reaches the configured size
          if batch_data.size >= config[:batch_size]
            process_batch(batch_data)
            batch_data.clear
          end

        rescue JSON::ParserError => e
          Rails.logger.warn("Invalid JSON at line #{line_count} in #{data_file}: #{e.message}")
          next
        rescue => e
          Rails.logger.error("Error processing line #{line_count} in #{data_file}: #{e.message}")
          next
        end
      end

      # Process remaining data
      if batch_data.any?
        process_batch(batch_data)
      end

      Rails.logger.info("Completed Oppadu collection from #{data_file}: #{line_count} lines processed")
    end

    def process_batch(batch_data)
      batch_data.each do |data|
        begin
          process_oppadu_item(data)
          @collected_items += 1

          # Log progress every 10 items
          if @collected_items % 10 == 0
            Rails.logger.info("Oppadu collection progress: #{@collected_items} items collected")
          end

        rescue => e
          Rails.logger.error("Error processing Oppadu item: #{e.message}")
          # Continue with next item
        end
      end
    end

    def process_oppadu_item(data)
      # Extract relevant information from Oppadu data
      item_id = data["id"] || data["url"] || generate_item_id(data)

      # Build thread data
      thread_data = {
        external_id: item_id,
        source: "oppadu",
        title: extract_title(data),
        content: extract_content(data),
        metadata: {
          original_url: data["url"],
          category: data["category"] || "general",
          difficulty: data["difficulty"] || classify_difficulty(data),
          tags: extract_tags(data),
          language: "ko",
          author: data["author"] || "Oppadu",
          published_date: parse_date(data["published_date"] || data["date"]),
          page_views: data["views"] || 0,
          rating: data["rating"] || 0
        }
      }

      # Check if already exists
      existing = KnowledgeThread.find_by(external_id: item_id, source: "oppadu")

      if existing
        # Update existing record
        existing.update!(
          title: thread_data[:title],
          content: thread_data[:content],
          metadata: thread_data[:metadata]
        )
      else
        # Create new record
        KnowledgeThread.create!(thread_data)
      end
    end

    def extract_title(data)
      data["title"] || data["question"] || data["subject"] || "Oppadu Excel Guide"
    end

    def extract_content(data)
      content_parts = []

      if data["question"]
        content_parts << "질문: #{data['question']}"
      end

      if data["answer"]
        content_parts << "답변: #{data['answer']}"
      end

      if data["content"]
        content_parts << data["content"]
      end

      if data["description"]
        content_parts << data["description"]
      end

      if data["steps"]
        content_parts << "단계별 설명:"
        data["steps"].each_with_index do |step, index|
          content_parts << "#{index + 1}. #{step}"
        end
      end

      content_parts.join("\n\n")
    end

    def extract_tags(data)
      tags = []

      tags.concat(data["tags"]) if data["tags"].is_a?(Array)
      tags.concat(data["keywords"]) if data["keywords"].is_a?(Array)
      tags << data["category"] if data["category"]

      # Extract Excel functions mentioned in content
      content = extract_content(data)
      excel_functions = extract_excel_functions(content)
      tags.concat(excel_functions)

      tags.compact.uniq
    end

    def extract_excel_functions(content)
      excel_functions = %w[
        합계 평균 개수 최대값 최소값 만약 찾아보기 색인 일치
        합계조건 개수조건 올림 내림 반올림 절댓값 그리고 또는 아니다 오류처리
        연결 왼쪽 오른쪽 중간 길이 날짜 오늘 지금 년 월 일 요일
        SUM AVERAGE COUNT MAX MIN IF VLOOKUP HLOOKUP INDEX MATCH
        SUMIF SUMIFS COUNTIF COUNTIFS ROUND ROUNDUP ROUNDDOWN ABS AND OR NOT IFERROR
        XLOOKUP FILTER SORT UNIQUE TEXTJOIN CONCATENATE LEFT RIGHT
        MID LEN DATE TODAY NOW YEAR MONTH DAY WEEKDAY
      ]

      found_functions = []
      content_processed = content.upcase

      excel_functions.each do |func|
        if content_processed.include?(func.upcase)
          found_functions << func
        end
      end

      found_functions.uniq
    end

    def classify_difficulty(data)
      content = extract_content(data).downcase

      complex_indicators = [
        "vlookup", "hlookup", "index", "match", "sumifs", "countifs",
        "pivot", "macro", "vba", "array", "nested", "complex",
        "찾아보기", "색인", "일치", "피벗", "매크로", "배열", "중첩"
      ]

      if complex_indicators.any? { |indicator| content.include?(indicator) }
        "complex"
      elsif content.length > 500
        "medium"
      else
        "simple"
      end
    end

    def parse_date(date_string)
      return Time.current unless date_string

      begin
        if date_string.is_a?(String)
          Time.parse(date_string)
        else
          date_string
        end
      rescue
        Time.current
      end
    end

    def generate_item_id(data)
      # Generate a unique ID based on content hash
      content = extract_content(data)
      title = extract_title(data)

      "oppadu_#{Digest::MD5.hexdigest("#{title}_#{content}")}"
    end
    end
  end
end
