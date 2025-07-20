# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Rails 8 application using **Vertical Slice Architecture** with features organized by business capability. Key architectural patterns:

- **Vertical Slices**: Features in `app/features/` contain handlers, services, and jobs
- **Domain-Driven Design**: Business logic organized in `app/domains/`
- **Multi-Provider AI**: Supports OpenAI, Anthropic, Google AI, and OpenRouter with automatic fallback
- **Component-Based UI**: ViewComponents + Stimulus + Vue.js for interactive features
- **Real-time Updates**: ActionCable with Solid Cable for live progress tracking

## Essential Commands

### Development
```bash
# Start all services (Rails + Vite + Redis)
bin/dev

# Run Rails server only
rails server -p 3003

# Database setup
rails db:create db:migrate db:seed

# Console access
rails console
```

### Testing
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/path/to/test_spec.rb

# Run single test (add line number)
bundle exec rspec spec/path/to/test_spec.rb:42

# Run tests matching pattern
bundle exec rspec spec/features/excel_analysis/

# JavaScript tests
npm run test:js
```

### Code Quality
```bash
# Ruby linting
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix

# JavaScript linting
npm run lint:js
npm run lint:js:fix

# Run all quality checks
rake quality:all
```

### Build & Deploy
```bash
# Build assets
rails assets:precompile
npm run build

# Deploy with Kamal
kamal deploy
```

## Project Structure

```
app/
├── features/           # Vertical slices by feature
│   ├── excel_analysis/    # Excel analysis feature
│   │   ├── handlers/      # Request handlers
│   │   ├── services/      # Business logic
│   │   └── jobs/          # Background jobs
│   ├── ai_integration/    # AI provider integration
│   └── payment_processing/# Payment handling
├── domains/            # Domain models and logic
├── components/         # ViewComponents for UI
├── infrastructure/     # External service adapters
├── javascript/         # Stimulus controllers + Vue
└── services/          # Shared application services
```

## Key Technologies

- **Excel Processing**: Roo (reading), RubyXL (manipulation), Fast_excel (15x faster), Xlsxtream (memory efficient)
- **AI Providers**: Multi-provider system with automatic fallback and rate limiting
- **Vector Search**: PostgreSQL with pgvector for RAG system
- **Real-time**: ActionCable + Solid Cable for WebSocket communication
- **Background Jobs**: Solid Queue with priority-based processing
- **Frontend**: Tailwind CSS + shadcn/ui components + Stimulus + Vue.js 3

## Development Patterns

### Error Handling
Use the Result pattern for consistent error handling:
```ruby
Result.success(data: processed_data)
Result.failure(error: "Processing failed", code: :processing_error)
```

### Feature Organization
Each feature follows this structure:
- `handlers/` - Handle HTTP requests, delegate to services
- `services/` - Business logic implementation
- `jobs/` - Background processing

### AI Integration
Multi-provider pattern with automatic fallback:
```ruby
# Services automatically retry with next provider on failure
MultiProviderService.new.analyze_excel(file, options)
```

### Testing Approach
- Unit tests for services and models
- Integration tests for features
- System tests for critical user flows
- Mock external services with WebMock/VCR

## Environment Setup

Required environment variables:
```bash
# AI Providers
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_AI_API_KEY=

# Database
DATABASE_URL=postgresql://...

# Redis
REDIS_URL=redis://...

# Optional: S3 for file storage
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_BUCKET=
```

## Common Tasks

### Adding a New Feature
1. Create feature directory: `app/features/your_feature/`
2. Add handler in `handlers/` for request processing
3. Implement service in `services/` for business logic
4. Create job in `jobs/` if background processing needed
5. Add tests in `spec/features/your_feature/`

### Working with Excel Files
- Use streaming processors for large files: `StreamingExcelProcessor`
- Formula analysis: `FormulaAnalysisService`
- Error detection: `ErrorDetector` service
- Always validate files before processing

### AI Provider Integration
- Check rate limits before requests
- Use caching for repeated queries
- Monitor costs with `AICostMonitoringController`
- Fallback order: OpenAI → Anthropic → Google AI → OpenRouter

### Database Migrations
```bash
# Create migration
rails generate migration AddFieldToModel field:type

# Run migrations
rails db:migrate

# Rollback if needed
rails db:rollback
```

## Important Notes

- **Security**: All user uploads are validated and sanitized
- **Performance**: Use streaming for large Excel files (>10MB)
- **Monitoring**: Sentry for errors, Scout APM for performance
- **Caching**: Redis caching enabled for AI responses
- **Internationalization**: Support for Korean (ko) and English (en)
- **Formula Engine**: External Node.js service handles complex Excel formulas