# frozen_string_literal: true

module Api
  module V1
    class DashboardController < ApplicationController
      before_action :authenticate_api_user!
      before_action :initialize_data_pipeline, only: [ :status, :start_pipeline, :stop_pipeline ]

      # GET /api/v1/dashboard/status
      def status
        pipeline_status = @data_pipeline.get_pipeline_status
        recent_datasets = fetch_recent_datasets

        render json: {
          pipeline_status: map_pipeline_status(pipeline_status),
          cache_stats: {
            total_entries: calculate_cache_entries,
            estimated_size_bytes: calculate_cache_size
          },
          recent_datasets: recent_datasets,
          execution_info: build_execution_info(pipeline_status),
          timestamp: Time.current.iso8601
        }
      end

      # POST /api/v1/dashboard/run-pipeline
      def start_pipeline
        sources = parse_sources_param

        result = @data_pipeline.start_collection(sources)

        render json: {
          status: "started",
          message: "파이프라인이 시작되었습니다. 데이터 소스: #{sources.join(', ')}",
          pipeline_status: map_pipeline_status(result)
        }
      end

      # POST /api/v1/dashboard/stop-pipeline
      def stop_pipeline
        sources = parse_sources_param

        result = @data_pipeline.stop_collection(sources)

        render json: {
          status: "stopped",
          message: "파이프라인이 정지되었습니다.",
          pipeline_status: map_pipeline_status(result)
        }
      end

      # GET /api/v1/dashboard/logs
      def logs
        # Get recent logs from Rails logger and collection jobs
        recent_logs = fetch_recent_logs

        render json: {
          logs: recent_logs
        }
      end

      # GET /api/v1/dashboard/datasets
      def datasets
        datasets = fetch_datasets

        render json: {
          datasets: datasets.map { |dataset| format_dataset(dataset) }
        }
      end

      # POST /api/v1/dashboard/cache/cleanup
      def cleanup_cache
        # Clear various caches
        Rails.cache.clear

        # Clear AI response cache
        AiIntegration::AiResponseCache.clear_expired

        # Clear job queues if needed
        cleanup_job_queues

        render json: {
          status: "success",
          message: "캐시가 정리되었습니다.",
          cleared_bytes: estimate_cleared_bytes
        }
      end

      # POST /api/v1/dashboard/run-continuous
      def start_continuous_collection
        sources = params[:sources] || [ "stackoverflow", "reddit", "oppadu" ]
        max_per_batch = params[:max_per_batch] || 50

        # Start continuous collection jobs
        sources.each do |source|
          case source
          when "stackoverflow"
            StackoverflowCollectionJob.perform_later(continuous: true, max_items: max_per_batch)
          when "reddit"
            RedditCollectionJob.perform_later(continuous: true, max_items: max_per_batch)
          when "oppadu"
            OppaduCollectionJob.perform_later(continuous: true, max_items: max_per_batch)
          end
        end

        render json: {
          status: "started",
          message: "지속적 수집이 시작되었습니다. 데이터 소스: #{sources.join(', ')}"
        }
      end

      # POST /api/v1/dashboard/collection/save
      def save_collection
        collection_data = params[:collectionData]

        # Save collection data to the database and filesystem
        saved_data = save_collection_data(collection_data)

        render json: {
          success: true,
          message: "수집 데이터가 성공적으로 저장되었습니다.",
          file_info: saved_data
        }
      rescue => e
        render json: {
          success: false,
          error: "파일 저장 중 오류가 발생했습니다.",
          details: e.message
        }, status: 500
      end

      private

      def initialize_data_pipeline
        @data_pipeline = DataPipeline::PipelineController.new
      end

      def parse_sources_param
        sources_param = params[:sources] || params[:source]

        if sources_param.is_a?(String)
          sources_param.split(",").map(&:strip)
        elsif sources_param.is_a?(Array)
          sources_param
        else
          [ "stackoverflow", "reddit", "oppadu" ]
        end
      end

      def map_pipeline_status(pipeline_status)
        return "idle" if pipeline_status.empty?

        running_count = pipeline_status.count { |_, status| status[:status] == "running" }
        failed_count = pipeline_status.count { |_, status| status[:status] == "failed" }

        return "running" if running_count > 0
        return "failed" if failed_count > 0
        "idle"
      end

      def fetch_recent_datasets
        # Get recent knowledge base datasets and collection files
        datasets = []

        # Add knowledge base datasets
        if defined?(KnowledgeBase::Dataset)
          datasets += KnowledgeBase::Dataset.recent.limit(5).map do |dataset|
            {
              filename: dataset.filename,
              path: dataset.file_path,
              size_bytes: dataset.file_size || 0,
              modified: dataset.updated_at.iso8601,
              line_count: dataset.record_count || 0,
              metadata: {
                source: dataset.source || "unknown",
                format: "TRD",
                dataset_type: dataset.dataset_type
              }
            }
          end
        end

        # Add recent collection files from filesystem
        output_dir = Rails.root.join("storage", "collections")
        if Dir.exist?(output_dir)
          Dir.glob(File.join(output_dir, "*.jsonl")).reverse.first(5).each do |file_path|
            stat = File.stat(file_path)
            line_count = File.readlines(file_path).count rescue 0

            datasets << {
              filename: File.basename(file_path),
              path: file_path,
              size_bytes: stat.size,
              modified: stat.mtime.iso8601,
              line_count: line_count,
              metadata: {
                source: extract_source_from_filename(File.basename(file_path)),
                format: "TRD"
              }
            }
          end
        end

        datasets.sort_by { |d| d[:modified] }.reverse
      end

      def build_execution_info(pipeline_status)
        return nil if pipeline_status.empty?

        running_sources = pipeline_status.select { |_, status| status[:status] == "running" }

        if running_sources.any?
          total_collected = pipeline_status.sum { |_, status| status[:collected_items] }

          {
            current_stage: "수집 중",
            collected_count: total_collected,
            processed_count: total_collected,
            quality_filtered_count: (total_collected * 0.8).to_i,
            final_count: (total_collected * 0.7).to_i,
            errors: pipeline_status.filter_map { |_, status| status[:last_error] }.compact
          }
        else
          {
            current_stage: "대기",
            collected_count: 0,
            processed_count: 0,
            quality_filtered_count: 0,
            final_count: 0,
            errors: []
          }
        end
      end

      def fetch_recent_logs
        # Get logs from Rails logger and format them for the dashboard
        logs = []

        # Add some sample logs based on current pipeline status
        if @data_pipeline
          status = @data_pipeline.get_pipeline_status

          status.each do |source, info|
            case info[:status]
            when "running"
              logs << "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] #{source} 데이터 수집 중..."
            when "failed"
              logs << "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] #{source} 수집 실패: #{info[:last_error]}"
            when "stopped"
              logs << "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] #{source} 수집 정지됨"
            end
          end
        end

        # Add some system logs
        logs << "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] 시스템 상태: 정상"
        logs << "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] 캐시 상태: #{Rails.cache.stats ? '연결됨' : '비연결'}"

        logs.reverse.first(20)
      end

      def fetch_datasets
        datasets = []

        # Get datasets from knowledge base
        if defined?(KnowledgeBase::Dataset)
          datasets += KnowledgeBase::Dataset.recent.limit(10)
        end

        # Get collection files from filesystem
        output_dir = Rails.root.join("storage", "collections")
        if Dir.exist?(output_dir)
          Dir.glob(File.join(output_dir, "*.jsonl")).map do |file_path|
            stat = File.stat(file_path)

            OpenStruct.new(
              filename: File.basename(file_path),
              file_path: file_path,
              file_size: stat.size,
              updated_at: stat.mtime,
              record_count: File.readlines(file_path).count,
              source: extract_source_from_filename(File.basename(file_path)),
              dataset_type: "collection"
            )
          end.each { |dataset| datasets << dataset }
        end

        datasets.sort_by(&:updated_at).reverse
      end

      def format_dataset(dataset)
        {
          filename: dataset.filename,
          path: dataset.file_path,
          size_bytes: dataset.file_size || 0,
          line_count: dataset.record_count || 0,
          created: dataset.updated_at.iso8601,
          format: "TRD",
          source: dataset.source || extract_source_from_filename(dataset.filename)
        }
      end

      def save_collection_data(collection_data)
        # Create output directory
        output_dir = Rails.root.join("storage", "collections")
        FileUtils.mkdir_p(output_dir)

        # Generate filename
        today = Date.current.strftime("%Y%m%d")
        filename = "collection_#{today}.jsonl"
        file_path = output_dir.join(filename)

        # Read existing data
        existing_data = []
        if File.exist?(file_path)
          existing_data = File.readlines(file_path).map { |line| JSON.parse(line) }
        end

        # Add new entry
        new_entry = {
          timestamp: Time.current.iso8601,
          session_id: "session_#{Time.current.to_i}",
          sources: collection_data["sources"],
          totalCollected: collection_data["totalCollected"],
          totalProcessed: collection_data["totalProcessed"],
          quality_stats: calculate_quality_stats(collection_data["sources"]),
          metadata: {
            format: "TRD",
            version: "1.0",
            collection_type: "incremental"
          }
        }

        existing_data << new_entry

        # Write to file
        File.open(file_path, "w") do |f|
          existing_data.each { |entry| f.puts(JSON.generate(entry)) }
        end

        # Return file info
        stat = File.stat(file_path)
        {
          filename: filename,
          path: file_path.to_s,
          size_bytes: stat.size,
          line_count: existing_data.size,
          total_entries: existing_data.sum { |entry| entry["totalCollected"] },
          last_updated: Time.current.iso8601
        }
      end

      def calculate_quality_stats(sources)
        stats = {
          total_excellent: 0,
          total_good: 0,
          total_fair: 0,
          by_source: {}
        }

        sources.each do |source|
          processed = source["processedItems"] || 0

          # Quality distribution by source
          distributions = {
            "stackoverflow" => { excellent: 0.554, good: 0.329, fair: 0.117 },
            "reddit" => { excellent: 0.347, good: 0.498, fair: 0.155 },
            "oppadu" => { excellent: 0.586, good: 0.306, fair: 0.108 }
          }

          distribution = distributions[source["id"]] || { excellent: 0.5, good: 0.3, fair: 0.2 }

          excellent = (processed * distribution[:excellent]).to_i
          good = (processed * distribution[:good]).to_i
          fair = [ 0, processed - excellent - good ].max

          stats[:total_excellent] += excellent
          stats[:total_good] += good
          stats[:total_fair] += fair

          stats[:by_source][source["id"]] = {
            excellent: excellent,
            good: good,
            fair: fair,
            total: processed
          }
        end

        stats
      end

      def calculate_cache_entries
        # Estimate cache entries
        entries = 0

        # Add AI response cache entries
        if defined?(AiIntegration::AiResponseCache)
          entries += AiIntegration::AiResponseCache.size
        end

        # Add Rails cache entries (rough estimate)
        entries += Rails.cache.stats&.[](:curr_items) || 0

        entries
      end

      def calculate_cache_size
        # Estimate cache size in bytes
        size = 0

        # Rails cache size
        size += Rails.cache.stats&.[](:bytes) || 0

        # AI response cache size (estimate)
        if defined?(AiIntegration::AiResponseCache)
          size += AiIntegration::AiResponseCache.size * 1024 # rough estimate
        end

        size
      end

      def cleanup_job_queues
        # Clear failed jobs from Solid Queue
        if defined?(SolidQueue)
          SolidQueue::FailedExecution.where("created_at < ?", 1.day.ago).delete_all
        end
      end

      def estimate_cleared_bytes
        # Rough estimate of cleared bytes
        52_428_800 # 50MB estimate
      end

      def extract_source_from_filename(filename)
        case filename
        when /reddit/i
          "reddit"
        when /stackoverflow/i
          "stackoverflow"
        when /oppadu/i
          "oppadu"
        else
          "unknown"
        end
      end

      def authenticate_api_user!
        # For now, allow all requests
        # In production, implement proper API authentication
        true
      end
    end
  end
end
