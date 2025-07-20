# frozen_string_literal: true

module Infrastructure
  module FileStorage
    class S3Service
      def initialize
        @use_s3 = ENV["AWS_ACCESS_KEY_ID"].present?

        if @use_s3
          @s3_client = Aws::S3::Client.new(
            region: ENV["AWS_REGION"] || "us-east-1",
            access_key_id: ENV["AWS_ACCESS_KEY_ID"],
            secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
          )
          @bucket = ENV["AWS_S3_BUCKET"] || "excelapp-files"
        end
      end

      def store(file, prefix: nil)
        if @use_s3
          store_to_s3(file, prefix)
        else
          store_locally(file, prefix)
        end
      end

      def retrieve(file_path)
        if @use_s3 && file_path.start_with?("s3://")
          retrieve_from_s3(file_path)
        else
          retrieve_locally(file_path)
        end
      end

      def delete(file_path)
        if @use_s3 && file_path.start_with?("s3://")
          delete_from_s3(file_path)
        else
          delete_locally(file_path)
        end
      end

      def url_for(file_path, expires_in: 3600)
        if @use_s3 && file_path.start_with?("s3://")
          generate_presigned_url(file_path, expires_in)
        else
          # Return local file URL
          "/files/#{file_path.gsub('storage/', '')}"
        end
      end

      private

      def store_to_s3(file, prefix)
        key = generate_key(file.original_filename, prefix)

        @s3_client.put_object(
          bucket: @bucket,
          key: key,
          body: file.read,
          content_type: file.content_type,
          server_side_encryption: "AES256"
        )

        "s3://#{@bucket}/#{key}"
      rescue StandardError => e
        Rails.logger.error("S3 upload failed: #{e.message}")
        raise
      end

      def store_locally(file, prefix)
        # Create storage directory if it doesn't exist
        storage_path = Rails.root.join("storage", prefix || "files")
        FileUtils.mkdir_p(storage_path)

        # Generate unique filename
        filename = "#{SecureRandom.uuid}_#{file.original_filename}"
        file_path = storage_path.join(filename)

        # Write file
        File.open(file_path, "wb") do |f|
          f.write(file.read)
        end

        "storage/#{prefix || 'files'}/#{filename}"
      end

      def retrieve_from_s3(file_path)
        key = file_path.gsub("s3://#{@bucket}/", "")

        response = @s3_client.get_object(
          bucket: @bucket,
          key: key
        )

        response.body
      rescue StandardError => e
        Rails.logger.error("S3 retrieval failed: #{e.message}")
        nil
      end

      def retrieve_locally(file_path)
        full_path = Rails.root.join(file_path)
        return nil unless File.exist?(full_path)

        File.read(full_path)
      end

      def delete_from_s3(file_path)
        key = file_path.gsub("s3://#{@bucket}/", "")

        @s3_client.delete_object(
          bucket: @bucket,
          key: key
        )

        true
      rescue StandardError => e
        Rails.logger.error("S3 deletion failed: #{e.message}")
        false
      end

      def delete_locally(file_path)
        full_path = Rails.root.join(file_path)
        return false unless File.exist?(full_path)

        File.delete(full_path)
        true
      rescue StandardError => e
        Rails.logger.error("Local file deletion failed: #{e.message}")
        false
      end

      def generate_presigned_url(file_path, expires_in)
        key = file_path.gsub("s3://#{@bucket}/", "")

        signer = Aws::S3::Presigner.new(client: @s3_client)
        signer.presigned_url(
          :get_object,
          bucket: @bucket,
          key: key,
          expires_in: expires_in
        )
      end

      def generate_key(filename, prefix)
        timestamp = Time.current.strftime("%Y%m%d%H%M%S")
        random = SecureRandom.hex(4)

        parts = [ prefix, timestamp, random, filename ].compact
        parts.join("/")
      end
    end
  end
end
