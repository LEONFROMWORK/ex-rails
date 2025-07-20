# frozen_string_literal: true

module DataPipeline
  module Jobs
    class StackoverflowCollectionJob < ApplicationJob
      queue_as :data_collection

      def perform(pipeline_controller:, source:)
        @pipeline_controller = pipeline_controller
        @source = source
        @collected_items = 0

        Rails.logger.info("Starting StackOverflow data collection")
        DataPipelineChannel.broadcast_collection_start(@source)

        begin
          collect_stackoverflow_data
          @pipeline_controller.on_collection_success(@source, @collected_items)
        rescue => e
          DataPipelineChannel.broadcast_error(@source, e.message)
          @pipeline_controller.on_collection_failure(@source, e)
          raise
        end
      end

      private

      def collect_stackoverflow_data
        # Configuration for StackOverflow collection
        config = {
          tags: [ "excel", "vba", "excel-formula", "excel-vba" ],
          batch_size: 100,
          rate_limit: 30, # API calls per minute
          max_pages: 10
        }

        config[:tags].each do |tag|
          collect_tag_data(tag, config)

          # Respect rate limits
          sleep(60.0 / config[:rate_limit])
        end
      end

      def collect_tag_data(tag, config)
        page = 1

        while page <= config[:max_pages]
          begin
            Rails.logger.info("Collecting StackOverflow data for tag: #{tag}, page: #{page}")

            questions = fetch_stackoverflow_questions(tag, page, config[:batch_size])

            if questions.any?
              process_questions(questions, tag)
              page += 1
            else
              break # No more questions available
            end

            # Small delay between pages
            sleep(1)

          rescue => e
            Rails.logger.error("Error collecting StackOverflow data for tag #{tag}, page #{page}: #{e.message}")

            # Continue with next page on error
            page += 1
          end
        end
      end

      def fetch_stackoverflow_questions(tag, page, batch_size)
        # This is a mock implementation
        # In a real implementation, this would call the StackOverflow API

        # For now, return mock data
        mock_questions = []

        batch_size.times do |i|
          mock_questions << {
            question_id: "q_#{tag}_#{page}_#{i}",
            title: "How to use #{tag} function in Excel?",
            body: "This is a sample question body about #{tag} functionality in Excel.",
            tags: [ tag, "excel" ],
            score: rand(0..50),
            answer_count: rand(0..5),
            is_answered: rand < 0.7,
            creation_date: rand(30.days).seconds.ago,
            answers: generate_mock_answers(rand(0..3))
          }
        end

        # Simulate API delay
        sleep(0.5)

        mock_questions
      end

      def generate_mock_answers(count)
        answers = []

        count.times do |i|
          answers << {
            answer_id: "ans_#{i}",
            body: "This is a sample answer explaining how to solve the Excel problem.",
            score: rand(0..30),
            is_accepted: i == 0 && rand < 0.3,
            creation_date: rand(29.days).seconds.ago
          }
        end

        answers
      end

      def process_questions(questions, tag)
        questions.each do |question|
          begin
            # Store in knowledge base
            thread_data = {
              external_id: question[:question_id],
              source: "stackoverflow",
              title: question[:title],
              content: question[:body],
              metadata: {
                tags: question[:tags],
                score: question[:score],
                answer_count: question[:answer_count],
                is_answered: question[:is_answered],
                creation_date: question[:creation_date]
              }
            }

            # Check if already exists
            existing = KnowledgeThread.find_by(external_id: question[:question_id], source: "stackoverflow")

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

            # Process answers
            if question[:answers]&.any?
              process_answers(question[:question_id], question[:answers])
            end

            @collected_items += 1

            # Broadcast item collected to real-time logs
            DataPipelineChannel.broadcast_item_collected(@source, {
              title: question[:title],
              content: question[:body],
              has_images: has_images?(question[:body])
            })

            # Log progress every 10 items
            if @collected_items % 10 == 0
              Rails.logger.info("StackOverflow collection progress: #{@collected_items} items collected")
              DataPipelineChannel.broadcast_batch_complete(@source, 10)
            end

          rescue => e
            Rails.logger.error("Error processing StackOverflow question #{question[:question_id]}: #{e.message}")
            # Continue with next question
          end
        end
      end

      def process_answers(question_id, answers)
        answers.each do |answer|
          begin
            # Store answer as additional context
            answer_data = {
              external_id: "#{question_id}_#{answer[:answer_id]}",
              source: "stackoverflow",
              title: "Answer for #{question_id}",
              content: answer[:body],
              metadata: {
                score: answer[:score],
                is_accepted: answer[:is_accepted],
                creation_date: answer[:creation_date],
                parent_question_id: question_id
              }
            }

            existing = KnowledgeThread.find_by(external_id: answer_data[:external_id], source: "stackoverflow")

            if existing
              existing.update!(
                content: answer_data[:content],
                metadata: answer_data[:metadata]
              )
            else
              KnowledgeThread.create!(answer_data)
            end

          rescue => e
            Rails.logger.error("Error processing StackOverflow answer #{answer[:answer_id]}: #{e.message}")
          end
        end
      end

      def has_images?(content)
        return false unless content

        content.downcase.include?("image") ||
        content.downcase.include?("img") ||
        content.downcase.include?("screenshot") ||
        content.downcase.include?("photo") ||
        content.downcase.include?("pic") ||
        content.include?("![") || # Markdown image
        content.include?("<img") # HTML image
      end
    end
  end
end
