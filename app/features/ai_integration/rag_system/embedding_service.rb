# frozen_string_literal: true

module AiIntegration
  module RagSystem
    class EmbeddingService
      EMBEDDING_MODEL = "text-embedding-3-small"
      EMBEDDING_DIMENSION = 1536
      MAX_CHUNK_SIZE = 8000

      def initialize
        @client = OpenAI::Client.new(access_token: openai_api_key)
        @cache = {}
      end

      def generate_embedding(text)
        # Check cache first
        cache_key = Digest::MD5.hexdigest(text)
        return @cache[cache_key] if @cache[cache_key]

        # Clean and prepare text
        cleaned_text = preprocess_text(text)

        # Split into chunks if too large
        chunks = split_into_chunks(cleaned_text)

        if chunks.size == 1
          # Single chunk
          embedding = generate_single_embedding(chunks.first)
        else
          # Multiple chunks - average embeddings
          embeddings = chunks.map { |chunk| generate_single_embedding(chunk) }
          embedding = average_embeddings(embeddings)
        end

        # Cache result
        @cache[cache_key] = embedding

        # Limit cache size
        if @cache.size > 1000
          @cache.shift(500)
        end

        embedding
      end

      def generate_batch_embeddings(texts)
        results = []

        texts.each_slice(20) do |batch|
          batch_results = batch.map { |text| generate_embedding(text) }
          results.concat(batch_results)

          # Rate limiting
          sleep(0.1) if batch.size > 10
        end

        results
      end

      def calculate_similarity(embedding1, embedding2)
        # Cosine similarity
        dot_product = embedding1.zip(embedding2).sum { |a, b| a * b }
        magnitude1 = Math.sqrt(embedding1.sum { |a| a * a })
        magnitude2 = Math.sqrt(embedding2.sum { |a| a * a })

        return 0.0 if magnitude1 == 0 || magnitude2 == 0

        dot_product / (magnitude1 * magnitude2)
      end

      def embedding_stats
        {
          model: EMBEDDING_MODEL,
          dimension: EMBEDDING_DIMENSION,
          cache_size: @cache.size,
          max_chunk_size: MAX_CHUNK_SIZE
        }
      end

      private

      def generate_single_embedding(text)
        response = @client.embeddings(
          parameters: {
            model: EMBEDDING_MODEL,
            input: text
          }
        )

        if response.dig("data", 0, "embedding")
          embedding = response["data"][0]["embedding"]

          # Validate embedding dimension
          if embedding.size != EMBEDDING_DIMENSION
            raise "Unexpected embedding dimension: #{embedding.size}, expected #{EMBEDDING_DIMENSION}"
          end

          Rails.logger.debug("Generated embedding for text (#{text.length} chars)")
          embedding
        else
          raise "Failed to generate embedding: #{response}"
        end
      rescue => e
        Rails.logger.error("Embedding generation failed: #{e.message}")
        raise
      end

      def preprocess_text(text)
        # Remove excessive whitespace
        text = text.gsub(/\s+/, " ").strip

        # Remove special characters that might cause issues
        text = text.gsub(/[^\w\s\-\.\,\!\?]/, " ")

        # Limit length
        text.truncate(MAX_CHUNK_SIZE)
      end

      def split_into_chunks(text)
        return [ text ] if text.length <= MAX_CHUNK_SIZE

        chunks = []
        current_chunk = ""

        # Split by sentences first
        sentences = text.split(/[.!?]+/)

        sentences.each do |sentence|
          sentence = sentence.strip
          next if sentence.empty?

          # If single sentence is too long, split by words
          if sentence.length > MAX_CHUNK_SIZE
            words = sentence.split(/\s+/)
            words.each do |word|
              if (current_chunk + " " + word).length > MAX_CHUNK_SIZE
                chunks << current_chunk.strip if current_chunk.strip.length > 0
                current_chunk = word
              else
                current_chunk += " " + word
              end
            end
          else
            # Check if adding this sentence would exceed limit
            if (current_chunk + " " + sentence).length > MAX_CHUNK_SIZE
              chunks << current_chunk.strip if current_chunk.strip.length > 0
              current_chunk = sentence
            else
              current_chunk += " " + sentence
            end
          end
        end

        # Add remaining chunk
        chunks << current_chunk.strip if current_chunk.strip.length > 0

        chunks
      end

      def average_embeddings(embeddings)
        return embeddings.first if embeddings.size == 1

        dimension = embeddings.first.size
        averaged = Array.new(dimension, 0.0)

        embeddings.each do |embedding|
          embedding.each_with_index do |value, index|
            averaged[index] += value
          end
        end

        # Divide by count to get average
        averaged.map! { |value| value / embeddings.size }

        averaged
      end

      def openai_api_key
        ENV["OPENAI_API_KEY"] || ENV["OPENROUTER_API_KEY"] || raise("No OpenAI API key configured")
      end
    end
  end
end
