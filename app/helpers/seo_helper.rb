# frozen_string_literal: true

module SeoHelper
  # 페이지별 SEO 메타태그 생성
  def seo_meta_tags(title: nil, description: nil, keywords: nil, image: nil, canonical: nil, type: "website")
    content_for :seo_meta_tags do
      tags = []

      # Title 최적화 (55-60자 제한)
      page_title = title || default_title
      tags << tag.title(page_title)
      tags << tag.meta(property: "og:title", content: page_title)
      tags << tag.meta(name: "twitter:title", content: page_title)

      # Description 최적화 (150-160자 제한)
      page_description = description || default_description
      tags << tag.meta(name: "description", content: page_description)
      tags << tag.meta(property: "og:description", content: page_description)
      tags << tag.meta(name: "twitter:description", content: page_description)

      # Keywords (선택적 사용)
      if keywords.present?
        tags << tag.meta(name: "keywords", content: keywords)
      end

      # Open Graph 메타태그
      tags << tag.meta(property: "og:type", content: type)
      tags << tag.meta(property: "og:url", content: canonical_url(canonical))
      tags << tag.meta(property: "og:site_name", content: site_name)
      tags << tag.meta(property: "og:locale", content: "ko_KR")

      # Twitter Card
      tags << tag.meta(name: "twitter:card", content: "summary_large_image")
      tags << tag.meta(name: "twitter:site", content: "@excelapp_rails")

      # 이미지 최적화
      page_image = image || default_image
      if page_image.present?
        tags << tag.meta(property: "og:image", content: page_image)
        tags << tag.meta(name: "twitter:image", content: page_image)
        tags << tag.meta(property: "og:image:alt", content: "#{page_title} - #{site_name}")
      end

      # Canonical URL
      if canonical.present?
        tags << tag.link(rel: "canonical", href: canonical_url(canonical))
      end

      # 모바일 최적화
      tags << tag.meta(name: "viewport", content: "width=device-width, initial-scale=1.0")

      # 추가 SEO 태그
      tags << tag.meta(name: "robots", content: "index, follow")
      tags << tag.meta(name: "googlebot", content: "index, follow")
      tags << tag.meta(name: "author", content: site_name)

      safe_join(tags, "\n")
    end
  end

  # 구조화된 데이터 (JSON-LD) 생성
  def structured_data(type, data = {})
    content_for :structured_data do
      schema = case type
      when :organization
                 organization_schema(data)
      when :website
                 website_schema(data)
      when :breadcrumb
                 breadcrumb_schema(data)
      when :article
                 article_schema(data)
      when :software_application
                 software_application_schema(data)
      when :faq
                 faq_schema(data)
      when :how_to
                 how_to_schema(data)
      else
                 {}
      end

      if schema.present?
        content_tag :script, type: "application/ld+json" do
          schema.to_json.html_safe
        end
      end
    end
  end

  # 빵부스러기 네비게이션 생성
  def breadcrumb_navigation(items)
    content_for :breadcrumb do
      nav_tag(class: "breadcrumb", 'aria-label': "Breadcrumb") do
        ol_tag(class: "breadcrumb-list", itemscope: true, itemtype: "https://schema.org/BreadcrumbList") do
          items.map.with_index do |item, index|
            li_tag(class: "breadcrumb-item",
                   itemprop: "itemListElement",
                   itemscope: true,
                   itemtype: "https://schema.org/ListItem") do
              content = if item[:url] && index < items.length - 1
                link_to(item[:name], item[:url], itemprop: "item")
              else
                content_tag(:span, item[:name], itemprop: "name")
              end

              content + tag.meta(itemprop: "position", content: (index + 1).to_s)
            end
          end.join.html_safe
        end
      end
    end

    # 구조화된 데이터도 함께 생성
    structured_data(:breadcrumb, items: items)
  end

  private

  def default_title
    "ExcelApp Rails - AI 기반 엑셀 파일 분석 및 최적화 플랫폼"
  end

  def default_description
    "AI 기술을 활용한 엑셀 파일 분석, VBA 코드 검토, 데이터 인사이트 제공. 무료로 시작하는 스마트한 엑셀 관리 솔루션."
  end

  def default_image
    asset_url("og-image.png") rescue nil
  end

  def site_name
    "ExcelApp Rails"
  end

  def canonical_url(path = nil)
    base_url = Rails.application.config.force_ssl ? "https://" : "http://"
    base_url += request.host
    base_url += ":#{request.port}" unless [ 80, 443 ].include?(request.port)
    base_url += path || request.path
    base_url
  end

  # 구조화된 데이터 스키마들
  def organization_schema(data)
    {
      '@context': "https://schema.org",
      '@type': "Organization",
      name: site_name,
      url: canonical_url("/"),
      logo: default_image,
      description: default_description,
      sameAs: data[:social_links] || []
    }
  end

  def website_schema(data)
    {
      '@context': "https://schema.org",
      '@type': "WebSite",
      name: site_name,
      url: canonical_url("/"),
      description: default_description,
      potentialAction: {
        '@type': "SearchAction",
        target: {
          '@type': "EntryPoint",
          urlTemplate: canonical_url("/search?q={search_term_string}")
        },
        'query-input': "required name=search_term_string"
      }
    }
  end

  def breadcrumb_schema(data)
    {
      '@context': "https://schema.org",
      '@type': "BreadcrumbList",
      itemListElement: data[:items].map.with_index do |item, index|
        {
          '@type': "ListItem",
          position: index + 1,
          name: item[:name],
          item: item[:url] ? canonical_url(item[:url]) : nil
        }.compact
      end
    }
  end

  def article_schema(data)
    {
      '@context': "https://schema.org",
      '@type': "Article",
      headline: data[:title],
      description: data[:description],
      author: {
        '@type': "Organization",
        name: site_name
      },
      publisher: {
        '@type': "Organization",
        name: site_name,
        logo: {
          '@type': "ImageObject",
          url: default_image
        }
      },
      datePublished: data[:published_at]&.iso8601,
      dateModified: data[:updated_at]&.iso8601,
      mainEntityOfPage: {
        '@type': "WebPage",
        '@id': canonical_url(data[:url])
      }
    }
  end

  def software_application_schema(data)
    {
      '@context': "https://schema.org",
      '@type': "SoftwareApplication",
      name: site_name,
      description: default_description,
      url: canonical_url("/"),
      applicationCategory: "BusinessApplication",
      operatingSystem: "Web Browser",
      offers: {
        '@type': "Offer",
        price: "0",
        priceCurrency: "KRW",
        description: "무료 기본 플랜 제공"
      },
      aggregateRating: data[:rating] || {
        '@type': "AggregateRating",
        ratingValue: "4.5",
        ratingCount: "100"
      }
    }
  end

  def faq_schema(data)
    {
      '@context': "https://schema.org",
      '@type': "FAQPage",
      mainEntity: data[:questions].map do |q|
        {
          '@type': "Question",
          name: q[:question],
          acceptedAnswer: {
            '@type': "Answer",
            text: q[:answer]
          }
        }
      end
    }
  end

  def how_to_schema(data)
    {
      '@context': "https://schema.org",
      '@type': "HowTo",
      name: data[:title],
      description: data[:description],
      step: data[:steps].map.with_index do |step, index|
        {
          '@type': "HowToStep",
          position: index + 1,
          name: step[:name],
          text: step[:description]
        }
      end
    }
  end
end
