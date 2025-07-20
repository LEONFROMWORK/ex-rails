# frozen_string_literal: true

module AiIntegration
  module Jobs
    class RagImportJob < ApplicationJob
      queue_as :default

      def perform(import_type, data_source, options = {})
        case import_type
        when "excel_knowledge"
          import_excel_knowledge(data_source, options)
        when "community_qa"
          import_community_qa(data_source, options)
        when "batch_documents"
          import_batch_documents(data_source, options)
        else
          raise ArgumentError, "Unknown import type: #{import_type}"
        end
      end

      private

      def import_excel_knowledge(data_source, options)
        orchestrator = RagOrchestrator.new

        case data_source
        when "oppadu"
          import_oppadu_data(orchestrator, options)
        when "stackoverflow"
          import_stackoverflow_data(orchestrator, options)
        when "reddit"
          import_reddit_data(orchestrator, options)
        when "file"
          import_file_data(orchestrator, options)
        else
          raise ArgumentError, "Unknown data source: #{data_source}"
        end
      end

      def import_oppadu_data(orchestrator, options)
      # Import from Oppadu data collection
      data_file = options[:file_path] || "/Users/kevin/bigdata/data/output/latest_oppadu_data.jsonl"

      unless File.exist?(data_file)
        Rails.logger.error("Oppadu data file not found: #{data_file}")
        return
      end

      documents = []
      line_count = 0

      File.foreach(data_file) do |line|
        line_count += 1
        next if line.strip.empty?

        begin
          data = JSON.parse(line)

          # Extract Q&A content
          if data["question"] && data["answer"]
            content = build_qa_content(data["question"], data["answer"])
            metadata = {
              source: "oppadu",
              language: "ko",
              url: data["url"],
              difficulty: classify_difficulty(data["question"]),
              functions: extract_excel_functions(content),
              imported_at: Time.current.iso8601
            }

            documents << { content: content, metadata: metadata }
          end

          # Batch import every 100 documents
          if documents.size >= 100
            orchestrator.batch_index_excel_knowledge(documents)
            documents.clear
            Rails.logger.info("Imported batch ending at line #{line_count}")
          end

        rescue JSON::ParserError => e
          Rails.logger.warn("Invalid JSON at line #{line_count}: #{e.message}")
          next
        end
      end

      # Import remaining documents
      if documents.any?
        orchestrator.batch_index_excel_knowledge(documents)
      end

      Rails.logger.info("Completed Oppadu import: #{line_count} lines processed")
      end

      def import_stackoverflow_data(orchestrator, options)
      # Import from StackOverflow API or dump
      # This would integrate with StackOverflow API
      Rails.logger.info("StackOverflow import not implemented yet")
      end

      def import_reddit_data(orchestrator, options)
      # Import from Reddit API
      Rails.logger.info("Reddit import not implemented yet")
      end

      def import_file_data(orchestrator, options)
      file_path = options[:file_path]
      format = options[:format] || "jsonl"

      unless File.exist?(file_path)
        Rails.logger.error("Import file not found: #{file_path}")
        return
      end

      case format
      when "jsonl"
          import_jsonl_file(orchestrator, file_path)
      when "csv"
          import_csv_file(orchestrator, file_path)
      when "json"
          import_json_file(orchestrator, file_path)
      else
          raise ArgumentError, "Unsupported format: #{format}"
      end
      end

      def import_jsonl_file(orchestrator, file_path)
      documents = []
      line_count = 0

      File.foreach(file_path) do |line|
        line_count += 1
        next if line.strip.empty?

        begin
          data = JSON.parse(line)

          if data["content"] || (data["question"] && data["answer"])
            content = data["content"] || build_qa_content(data["question"], data["answer"])
            metadata = data["metadata"] || {}

            documents << { content: content, metadata: metadata }
          end

          # Batch import every 50 documents
          if documents.size >= 50
            orchestrator.batch_index_excel_knowledge(documents)
            documents.clear
            Rails.logger.info("Imported batch ending at line #{line_count}")
          end

        rescue JSON::ParserError => e
          Rails.logger.warn("Invalid JSON at line #{line_count}: #{e.message}")
          next
        end
      end

      # Import remaining documents
      if documents.any?
        orchestrator.batch_index_excel_knowledge(documents)
      end

      Rails.logger.info("Completed JSONL import: #{line_count} lines processed")
      end

      def import_csv_file(orchestrator, file_path)
      require "csv"

      documents = []
      row_count = 0

      CSV.foreach(file_path, headers: true) do |row|
        row_count += 1

        if row["content"] || (row["question"] && row["answer"])
          content = row["content"] || build_qa_content(row["question"], row["answer"])
          metadata = {
            source: row["source"] || "csv_import",
            language: row["language"] || "en",
            difficulty: row["difficulty"] || "medium"
          }

          documents << { content: content, metadata: metadata }
        end

        # Batch import every 50 documents
        if documents.size >= 50
          orchestrator.batch_index_excel_knowledge(documents)
          documents.clear
          Rails.logger.info("Imported batch ending at row #{row_count}")
        end
      end

      # Import remaining documents
      if documents.any?
        orchestrator.batch_index_excel_knowledge(documents)
      end

      Rails.logger.info("Completed CSV import: #{row_count} rows processed")
      end

      def import_json_file(orchestrator, file_path)
      data = JSON.parse(File.read(file_path))
      documents = []

      case data
      when Array
        data.each do |item|
          if item["content"] || (item["question"] && item["answer"])
            content = item["content"] || build_qa_content(item["question"], item["answer"])
            metadata = item["metadata"] || {}

            documents << { content: content, metadata: metadata }
          end
        end
      when Hash
        if data["documents"]
          data["documents"].each do |item|
            if item["content"] || (item["question"] && item["answer"])
              content = item["content"] || build_qa_content(item["question"], item["answer"])
              metadata = item["metadata"] || {}

              documents << { content: content, metadata: metadata }
            end
          end
        end
      end

      if documents.any?
        orchestrator.batch_index_excel_knowledge(documents)
        Rails.logger.info("Completed JSON import: #{documents.size} documents processed")
      end
      end

      def import_community_qa(data_source, options)
      # Import community Q&A data
      Rails.logger.info("Community Q&A import for #{data_source} not implemented yet")
      end

      def import_batch_documents(data_source, options)
      # Import batch documents from various sources
      Rails.logger.info("Batch document import for #{data_source} not implemented yet")
      end

      def build_qa_content(question, answer)
      content_parts = []

      content_parts << "Q: #{question.strip}"
      content_parts << "A: #{answer.strip}" if answer.present?

      content_parts.join("\n\n")
      end

      def classify_difficulty(question)
      complex_indicators = [
        "vlookup", "hlookup", "index", "match", "sumifs", "countifs",
        "pivot", "macro", "vba", "array", "nested", "complex"
      ]

      question_lower = question.downcase

      if complex_indicators.any? { |indicator| question_lower.include?(indicator) }
        "complex"
      elsif question_lower.length > 200
        "medium"
      else
        "simple"
      end
      end

      def extract_excel_functions(content)
      excel_functions = %w[
        SUM AVERAGE COUNT MAX MIN IF VLOOKUP HLOOKUP INDEX MATCH
        SUMIF SUMIFS COUNTIF COUNTIFS ROUND ABS AND OR NOT IFERROR
        XLOOKUP FILTER SORT UNIQUE TEXTJOIN CONCATENATE LEFT RIGHT
        MID LEN DATE TODAY NOW YEAR MONTH DAY WEEKDAY
      ]

      found_functions = []
      content_upper = content.upcase

      excel_functions.each do |func|
        if content_upper.include?(func)
          found_functions << func
        end
      end

      found_functions.uniq
      end
    end
  end
end
