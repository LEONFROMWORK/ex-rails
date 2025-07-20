# frozen_string_literal: true

class SitemapController < ApplicationController
  def index
    respond_to do |format|
      format.xml do
        @static_pages = static_page_urls
        @dynamic_pages = dynamic_page_urls

        render template: "sitemap/index", layout: false
      end
    end
  end

  private

  def static_page_urls
    [
      {
        loc: root_url,
        lastmod: 1.week.ago,
        changefreq: "daily",
        priority: 1.0
      },
      {
        loc: url_for(controller: "users/registrations", action: "new"),
        lastmod: 1.month.ago,
        changefreq: "monthly",
        priority: 0.8
      },
      {
        loc: url_for(controller: "users/sessions", action: "new"),
        lastmod: 1.month.ago,
        changefreq: "monthly",
        priority: 0.6
      },
      {
        loc: url_for(controller: "dashboard", action: "index"),
        lastmod: 1.week.ago,
        changefreq: "weekly",
        priority: 0.8
      }
    ]
  end

  def dynamic_page_urls
    urls = []

    # 공개적으로 접근 가능한 도움말 페이지들 (예시)
    help_pages = [
      "getting-started",
      "faq",
      "pricing",
      "features",
      "api-documentation"
    ]

    help_pages.each do |page|
      urls << {
        loc: "#{root_url}help/#{page}",
        lastmod: 2.weeks.ago,
        changefreq: "monthly",
        priority: 0.6
      }
    end

    urls
  end
end
