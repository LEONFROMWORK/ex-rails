Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA routes
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Root route
  root "home#index"
  get "theme_test", to: "home#theme_test"

  # Vue.js demo routes
  get "vue", to: "vue#index"
  get "vue/test", to: "vue#test"
  get "vue/status", to: "vue#status"

  # Authentication routes
  namespace :auth do
    get "register", to: "registrations#new", as: "signup"
    post "register", to: "registrations#create"
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"
  end

  # OAuth routes
  get "/auth/:provider/callback", to: "auth/sessions#omniauth", as: "omniauth_callback"
  get "/auth/failure", to: "auth/sessions#failure"

  # User routes
  resources :users, only: [ :show, :edit, :update ] do
    member do
      get :profile
      patch :update_profile
      get :subscription
      patch :update_subscription
    end
  end

  # Excel file management
  resources :excel_files do
    member do
      get :download
      get :analysis_results
      post :reanalyze
      get :progress
      # FormulaEngine analysis routes
      post :analyze_formulas
      get :formula_results
    end

    # VBA analysis routes
    post :analyze_vba, on: :member
    get :vba_results, on: :member
  end

  # Excel Analysis domain routes
  namespace :excel_analysis do
    resources :files, only: [ :create, :show, :update ] do
      member do
        post :analyze
        post :analyze_vba
        get :vba_security_scan
        get :vba_performance_analysis
        get :analysis_progress
      end
    end

    # Image analysis routes (Gemini multimodal)
    post "analyze_image", to: "image_analysis#analyze"
    post "analyze_chart", to: "image_analysis#analyze_chart"
    post "analyze_formula_screenshot", to: "image_analysis#analyze_formula"
    post "analyze_video_tutorial", to: "image_analysis#analyze_video"
  end

  # Excel Generation domain routes
  namespace :excel_generation do
    # Template-based generation
    get "templates", to: "templates#index"
    get "templates/:category", to: "templates#category"
    get "templates/:category/:template_name", to: "templates#show"
    get "templates/:category/:template_name/preview", to: "templates#preview"
    post "from_template", to: "generation#from_template"

    # Conversation-based generation
    post "from_conversation", to: "generation#from_conversation"
    get "conversation_builder", to: "generation#conversation_builder"

    # Large dataset generation
    post "large_dataset", to: "generation#large_dataset"

    # File downloads
    get "download/:file_id", to: "generation#download"

    # Generation progress
    get "progress/:generation_id", to: "generation#progress"
  end

  # AI Integration routes
  namespace :ai_integration do
    # Chat functionality
    resources :chat_conversations, only: [ :index, :create, :show ] do
      resources :messages, only: [ :create ]
      member do
        post :regenerate_response
        delete :clear_history
      end
    end

    # Multimodal AI routes
    post "multimodal/analyze_image", to: "multimodal#analyze_image"
    post "multimodal/analyze_video", to: "multimodal#analyze_video"
    post "multimodal/analyze_with_context", to: "multimodal#analyze_with_context"
  end

  # Analysis management
  resources :analyses, only: [ :index, :show, :destroy ] do
    member do
      get :export
      post :share
    end
  end

  # Admin routes
  namespace :admin do
    get "/", to: "dashboard#index"
    get "dashboard", to: "dashboard#index"
    get "analytics", to: "dashboard#analytics"

    resources :users do
      member do
        patch :update_tier
        patch :adjust_tokens
        post :send_notification
      end
    end

    resources :system_monitoring, only: [ :index ] do
      collection do
        get :queue_performance
        get :ai_usage_stats
        get :performance_metrics
        post :optimize_queues
        post :emergency_scaling
      end
    end

    # Advanced analytics
    get "advanced_analytics", to: "advanced_analytics#index"
    get "advanced_analytics/real_time", to: "advanced_analytics#real_time"
  end

  # Payment and subscription routes
  namespace :payments do
    resources :subscriptions, only: [ :show, :create, :update, :destroy ] do
      collection do
        get :plans
        post :change_plan
      end
    end

    resources :payments, only: [ :create, :show ] do
      collection do
        post :toss_webhook
        get :success
        get :failure
      end
    end

    # Token purchases
    post "purchase_tokens", to: "tokens#purchase"
    get "token_packages", to: "tokens#packages"
  end

  # API routes
  namespace :api do
    namespace :v1 do
      # Authentication
      post "auth/login", to: "auth#login"
      post "auth/logout", to: "auth#logout"
      post "auth/refresh", to: "auth#refresh"

      # Excel file operations
      resources :files, only: [ :create, :show, :update, :destroy ] do
        member do
          post :analyze
          post :analyze_vba
          get :analysis_status
          get :analysis_results
          get :download
          post :cancel
          get :formula_analysis  # 새로운 FormulaEngine 전용 엔드포인트
        end
      end

      # AI analysis
      post "ai/analyze_excel", to: "ai#analyze_excel"
      post "ai/analyze_image", to: "ai#analyze_image"
      post "ai/analyze_vba", to: "ai#analyze_vba"

      # Excel modifications with AI
      get "excel_modifications/recommend_tier", to: "excel_modifications#recommend_tier"
      post "excel_modifications/modify", to: "excel_modifications#modify"
      post "excel_modifications/convert_to_formula", to: "excel_modifications#convert_to_formula"

      # Excel generation
      post "generation/from_template", to: "generation#from_template"
      post "generation/from_conversation", to: "generation#from_conversation"
      get "generation/templates", to: "generation#templates"

      # Chat
      resources :chat, only: [ :create, :show ] do
        collection do
          post :send_message
          get :history
        end
      end

      # PipeData integration
      post "pipedata", to: "pipedata#create"
      get "pipedata", to: "pipedata#show"

      # Payment routes
      post "payments/request", to: "payments#request"
      post "payments/approve", to: "payments#approve"
      resources :payments, only: [ :index, :show ] do
        member do
          post :cancel
        end
      end
      post "payments/billing_key", to: "payments#issue_billing_key"
      post "payments/billing", to: "payments#pay_with_billing"

      # Webhook routes
      post "payment_webhooks", to: "payment_webhooks#create"

      # System stats (for external monitoring)
      get "system/health", to: "system#health"
      get "system/metrics", to: "system#metrics"
    end
  end

  # WebSocket routes for ActionCable
  mount ActionCable.server => "/cable"

  # SEO routes
  get "sitemap.xml", to: "sitemap#index", defaults: { format: "xml" }

  # Error handling routes
  match "/404", to: "errors#not_found", via: :all
  match "/500", to: "errors#internal_server_error", via: :all
  match "/422", to: "errors#unprocessable_entity", via: :all
end
