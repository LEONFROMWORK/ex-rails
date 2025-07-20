# frozen_string_literal: true

module DataPipeline
  module Jobs
    class RedditCollectionJob < ApplicationJob
    queue_as :data_collection

    def perform(pipeline_controller:, source:)
      @pipeline_controller = pipeline_controller
      @source = source
      @collected_items = 0

      Rails.logger.info("Starting Reddit data collection")
      DataPipelineChannel.broadcast_collection_start(@source)

      begin
        collect_reddit_data
        @pipeline_controller.on_collection_success(@source, @collected_items)
      rescue => e
        DataPipelineChannel.broadcast_error(@source, e.message)
        @pipeline_controller.on_collection_failure(@source, e)
        raise
      end
    end

    private

    def collect_reddit_data
      # Configuration for Reddit collection
      config = {
        subreddits: [ "excel", "ExcelTips", "vba" ],
        batch_size: 100,
        rate_limit: 60, # requests per minute
        max_pages: 5
      }

      config[:subreddits].each do |subreddit|
        collect_subreddit_data(subreddit, config)

        # Respect rate limits
        sleep(60.0 / config[:rate_limit])
      end
    end

    def collect_subreddit_data(subreddit, config)
      page = 1
      after_token = nil

      while page <= config[:max_pages]
        begin
          Rails.logger.info("Collecting Reddit data for subreddit: #{subreddit}, page: #{page}")

          # Simulate API call - replace with actual Reddit API integration
          result = fetch_reddit_posts(subreddit, after_token, config[:batch_size])
          posts = result[:posts]
          after_token = result[:after]

          break if posts.empty?

          process_posts(posts, subreddit)

          page += 1

          # Small delay between pages
          sleep(1)

        rescue => e
          Rails.logger.error("Error collecting Reddit data for subreddit #{subreddit}, page #{page}: #{e.message}")

          # Continue with next page on error
          page += 1
        end
      end
    end

    def fetch_reddit_posts(subreddit, after_token, batch_size)
      # This is a mock implementation
      # In a real implementation, this would call the Reddit API

      # For now, return mock data
      mock_posts = []

      batch_size.times do |i|
        mock_posts << {
          post_id: "reddit_#{subreddit}_#{after_token}_#{i}",
          title: "Excel help needed with #{[ 'VLOOKUP', 'Pivot Tables', 'VBA', 'Formulas' ].sample} - Post #{i}",
          body: "I'm having trouble with Excel and need help with this specific problem...",
          author: "user_#{i}",
          score: rand(0..100),
          num_comments: rand(0..20),
          created_utc: rand(30.days).seconds.ago,
          url: "https://reddit.com/r/#{subreddit}/comments/#{i}",
          is_self: true,
          comments: generate_mock_comments(rand(0..5))
        }
      end

      # Simulate API delay
      sleep(0.5)

      {
        posts: mock_posts,
        after: "after_#{after_token}_#{batch_size}"
      }
    end

    def generate_mock_comments(count)
      comments = []

      count.times do |i|
        comments << {
          comment_id: "comment_#{i}",
          body: "Here's a possible solution to your Excel problem...",
          author: "helper_#{i}",
          score: rand(0..20),
          created_utc: rand(29.days).seconds.ago,
          is_op_reply: i == 0 && rand < 0.3
        }
      end

      comments
    end

    def process_posts(posts, subreddit)
      posts.each do |post|
        begin
          # Store in knowledge base
          thread_data = {
            external_id: post[:post_id],
            source: "reddit",
            title: post[:title],
            content: post[:body],
            metadata: {
              subreddit: subreddit,
              author: post[:author],
              score: post[:score],
              num_comments: post[:num_comments],
              created_utc: post[:created_utc],
              url: post[:url],
              is_self: post[:is_self]
            }
          }

          # Check if already exists
          existing = KnowledgeThread.find_by(external_id: post[:post_id], source: "reddit")

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

          # Process comments
          if post[:comments]&.any?
            process_comments(post[:post_id], post[:comments])
          end

          @collected_items += 1

          # Log progress every 10 items
          if @collected_items % 10 == 0
            Rails.logger.info("Reddit collection progress: #{@collected_items} items collected")
          end

        rescue => e
          Rails.logger.error("Error processing Reddit post #{post[:post_id]}: #{e.message}")
          # Continue with next post
        end
      end
    end

    def process_comments(post_id, comments)
      comments.each do |comment|
        begin
          # Store comment as additional context
          comment_data = {
            external_id: "#{post_id}_#{comment[:comment_id]}",
            source: "reddit",
            title: "Comment on Reddit post #{post_id}",
            content: comment[:body],
            metadata: {
              parent_post_id: post_id,
              author: comment[:author],
              score: comment[:score],
              created_utc: comment[:created_utc],
              is_op_reply: comment[:is_op_reply]
            }
          }

          existing = KnowledgeThread.find_by(external_id: comment_data[:external_id], source: "reddit")

          if existing
            existing.update!(
              content: comment_data[:content],
              metadata: comment_data[:metadata]
            )
          else
            KnowledgeThread.create!(comment_data)
          end

        rescue => e
          Rails.logger.error("Error processing Reddit comment #{comment[:comment_id]}: #{e.message}")
        end
      end
    end
    end
  end
end
