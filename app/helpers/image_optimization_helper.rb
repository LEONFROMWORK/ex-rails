# frozen_string_literal: true

module ImageOptimizationHelper
  # 반응형 이미지 태그 생성
  def responsive_image_tag(source, alt_text, **options)
    # 기본 설정
    default_options = {
      loading: "lazy",
      decoding: "async",
      class: options[:class] || "",
      sizes: options[:sizes] || "(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
    }

    # 옵션 병합
    merged_options = default_options.merge(options.except(:sizes, :srcset))

    # srcset이 제공된 경우
    if options[:srcset].present?
      merged_options[:srcset] = options[:srcset]
    end

    # alt 텍스트는 필수
    merged_options[:alt] = alt_text

    image_tag(source, **merged_options)
  end

  # WebP 지원 여부에 따른 이미지 포맷 선택
  def optimized_image_tag(source, alt_text, **options)
    base_name = File.basename(source, ".*")
    extension = File.extname(source)
    webp_source = source.gsub(extension, ".webp")

    content_tag :picture, **options.slice(:class, :id) do
      concat(tag.source(srcset: asset_path(webp_source), type: "image/webp"))
      concat(responsive_image_tag(source, alt_text, **options.except(:class, :id)))
    end
  end

  # 아이콘 SVG 최적화
  def optimized_icon(name, **options)
    default_options = {
      class: "inline-block",
      'aria-hidden': "true",
      focusable: "false"
    }

    merged_options = default_options.merge(options)

    # SVG 아이콘 인라인 삽입 (성능 최적화)
    case name.to_s
    when "loading"
      content_tag :svg, merged_options.merge(
        viewBox: "0 0 24 24",
        fill: "none",
        stroke: "currentColor"
      ) do
        tag.path(
          'stroke-linecap': "round",
          'stroke-linejoin': "round",
          'stroke-width': "2",
          d: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
        )
      end
    when "error"
      content_tag :svg, merged_options.merge(
        viewBox: "0 0 20 20",
        fill: "currentColor"
      ) do
        tag.path(
          'fill-rule': "evenodd",
          d: "M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z",
          'clip-rule': "evenodd"
        )
      end
    when "success"
      content_tag :svg, merged_options.merge(
        viewBox: "0 0 20 20",
        fill: "currentColor"
      ) do
        tag.path(
          'fill-rule': "evenodd",
          d: "M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z",
          'clip-rule': "evenodd"
        )
      end
    else
      # 외부 아이콘 파일 사용
      image_tag("icons/#{name}.svg", **merged_options)
    end
  end

  # 이미지 프리로드 힌트 생성
  def preload_images(*sources)
    sources.flatten.map do |source|
      if source.end_with?(".webp")
        tag.link(rel: "preload", as: "image", href: asset_path(source), type: "image/webp")
      else
        tag.link(rel: "preload", as: "image", href: asset_path(source))
      end
    end.join.html_safe
  end

  # 중요하지 않은 이미지의 지연 로딩 설정
  def lazy_image_tag(source, alt_text, **options)
    default_options = {
      loading: "lazy",
      decoding: "async",
      class: "#{options[:class]} transition-opacity duration-300",
      'data-src': asset_path(source),
      src: "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAiIGhlaWdodD0iMTAiIHZpZXdCb3g9IjAgMCAxMCAxMCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48L3N2Zz4="
    }

    merged_options = default_options.merge(options.except(:class))
    merged_options[:alt] = alt_text

    image_tag("", **merged_options)
  end

  # 이미지 크기 최적화 정보
  def image_dimensions(source)
    # 실제 구현에서는 이미지 파일을 읽어 크기를 반환
    # 여기서는 예시로 기본값 반환
    {
      width: 800,
      height: 600,
      aspect_ratio: "4:3"
    }
  end
end
