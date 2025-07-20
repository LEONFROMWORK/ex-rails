module ExcelModification
  module Services
    class ScreenshotQualityValidator
      include Common::ResultHandler

      MIN_WIDTH = 400
      MIN_HEIGHT = 300
      MIN_FILE_SIZE = 10.kilobytes
      MAX_FILE_SIZE = 10.megabytes
      SUPPORTED_FORMATS = %w[image/png image/jpeg image/jpg image/webp].freeze

      def initialize
        @logger = Rails.logger
      end

      def validate(screenshot_data)
        return failure("Screenshot data is required") if screenshot_data.blank?

        # Base64 데이터인 경우 처리
        if screenshot_data.is_a?(String) && screenshot_data.include?("base64,")
          validate_base64_screenshot(screenshot_data)
        elsif screenshot_data.respond_to?(:read)
          validate_file_screenshot(screenshot_data)
        else
          failure("Invalid screenshot format")
        end
      rescue => e
        @logger.error "Screenshot validation error: #{e.message}"
        failure("Failed to validate screenshot: #{e.message}")
      end

      private

      def validate_base64_screenshot(base64_data)
        # Extract base64 content
        base64_content = base64_data.split("base64,").last
        image_data = Base64.decode64(base64_content)

        # Check file size
        file_size = image_data.bytesize
        return failure("Screenshot is too small (#{number_to_human_size(file_size)}). Please upload a clearer image.") if file_size < MIN_FILE_SIZE
        return failure("Screenshot is too large (#{number_to_human_size(file_size)}). Maximum size is 10MB.") if file_size > MAX_FILE_SIZE

        # Create tempfile to analyze with MiniMagick
        tempfile = Tempfile.new([ "screenshot", ".png" ])
        tempfile.binmode
        tempfile.write(image_data)
        tempfile.rewind

        analyze_image_quality(tempfile)
      ensure
        tempfile&.close
        tempfile&.unlink
      end

      def validate_file_screenshot(file)
        # Check MIME type
        mime_type = Marcel::MimeType.for(file)
        unless SUPPORTED_FORMATS.include?(mime_type)
          return failure("Unsupported image format. Please upload PNG, JPEG, or WebP.")
        end

        # Check file size
        file_size = file.size
        return failure("Screenshot is too small (#{number_to_human_size(file_size)}). Please upload a clearer image.") if file_size < MIN_FILE_SIZE
        return failure("Screenshot is too large (#{number_to_human_size(file_size)}). Maximum size is 10MB.") if file_size > MAX_FILE_SIZE

        analyze_image_quality(file)
      end

      def analyze_image_quality(image_file)
        image = MiniMagick::Image.new(image_file.path)

        width = image.width
        height = image.height

        # Check dimensions
        if width < MIN_WIDTH || height < MIN_HEIGHT
          return failure(
            "Screenshot resolution is too low (#{width}x#{height}). " \
            "Please upload a higher resolution image (minimum #{MIN_WIDTH}x#{MIN_HEIGHT})."
          )
        end

        # Calculate quality score
        quality_score = calculate_quality_score(image)

        if quality_score < 0.3
          return failure(
            "Screenshot quality is too low. Please ensure:\n" \
            "• The image is clear and not blurry\n" \
            "• Text is readable\n" \
            "• The Excel content is clearly visible"
          )
        end

        success({
          width: width,
          height: height,
          format: image.mime_type,
          size: image_file.size,
          quality_score: quality_score,
          quality_level: quality_level(quality_score)
        })
      rescue MiniMagick::Error => e
        failure("Failed to process image: #{e.message}")
      end

      def calculate_quality_score(image)
        # Simple quality estimation based on multiple factors
        score = 1.0

        # Penalize very small images
        resolution = image.width * image.height
        if resolution < 640 * 480
          score *= 0.5
        elsif resolution < 1024 * 768
          score *= 0.8
        end

        # Check if image might be compressed (simplified check)
        # In real implementation, we might use more sophisticated methods
        if image["quality"] && image["quality"].to_i < 70
          score *= 0.7
        end

        score
      end

      def quality_level(score)
        case score
        when 0.8..1.0
          :excellent
        when 0.6...0.8
          :good
        when 0.4...0.6
          :acceptable
        else
          :poor
        end
      end

      def number_to_human_size(size)
        ActionController::Base.helpers.number_to_human_size(size)
      end
    end
  end
end
