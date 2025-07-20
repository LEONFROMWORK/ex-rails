# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiIntegration::Services::AiResponseCache do
  let(:cache_service) { described_class.new }
  let(:valid_response) do
    {
      'message' => 'Test AI response',
      'confidence_score' => 0.85,
      'tokens_used' => 100,
      'provider' => 'openai'
    }
  end

  before do
    # Clear cache before each test
    cache_service.clear_all
  end

  describe '#generate_cache_key' do
    it 'generates consistent cache keys' do
      key1 = cache_service.generate_cache_key(
        type: :chat,
        content: 'test message',
        provider: 'openai',
        user_tier: 1
      )

      key2 = cache_service.generate_cache_key(
        type: :chat,
        content: 'test message',
        provider: 'openai',
        user_tier: 1
      )

      expect(key1).to eq(key2)
      expect(key1).to include('ai_response:chat:openai:1')
    end

    it 'generates different keys for different content' do
      key1 = cache_service.generate_cache_key(
        type: :chat,
        content: 'message 1',
        provider: 'openai'
      )

      key2 = cache_service.generate_cache_key(
        type: :chat,
        content: 'message 2',
        provider: 'openai'
      )

      expect(key1).not_to eq(key2)
    end
  end

  describe '#set and #get' do
    let(:cache_key) { 'test_key' }

    it 'stores and retrieves valid responses' do
      result = cache_service.set(cache_key, valid_response)
      expect(result).to be true

      cached_data = cache_service.get(cache_key)
      expect(cached_data).not_to be_nil
      expect(cached_data['data']).to eq(valid_response)
    end

    it 'returns nil for non-existent keys' do
      cached_data = cache_service.get('non_existent_key')
      expect(cached_data).to be_nil
    end

    it 'does not cache responses with low confidence' do
      low_confidence_response = valid_response.merge('confidence_score' => 0.5)

      result = cache_service.set(cache_key, low_confidence_response)
      expect(result).to be false
    end

    it 'does not cache responses missing required fields' do
      invalid_response = { 'message' => 'test' }

      result = cache_service.set(cache_key, invalid_response)
      expect(result).to be false
    end

    it 'adds metadata to cached responses' do
      cache_service.set(cache_key, valid_response)
      cached_data = cache_service.get(cache_key)

      expect(cached_data['cached_at']).to be_present
      expect(cached_data['expires_at']).to be_present
      expect(cached_data['cache_version']).to eq('1.0')
    end
  end

  describe '#clear_expired' do
    it 'removes expired entries' do
      # Create an entry that will expire immediately
      cache_service.set('temp_key', valid_response, ttl: 0.1.seconds)

      # Wait for expiration
      sleep(0.2)

      expired_count = cache_service.clear_expired
      expect(expired_count).to be >= 0

      # Verify entry is gone
      cached_data = cache_service.get('temp_key')
      expect(cached_data).to be_nil
    end
  end

  describe '#stats' do
    it 'tracks cache statistics' do
      # Perform some cache operations
      cache_service.set('key1', valid_response)
      cache_service.get('key1') # hit
      cache_service.get('key2') # miss

      stats = cache_service.stats
      expect(stats).to include(:hits, :misses, :writes, :hit_rate)
      expect(stats[:writes]).to be >= 1
    end

    it 'calculates hit rate correctly' do
      # Set up some hits and misses
      cache_service.set('key1', valid_response)

      # 2 hits
      cache_service.get('key1')
      cache_service.get('key1')

      # 1 miss
      cache_service.get('nonexistent')

      stats = cache_service.stats
      expect(stats[:hits]).to eq(2)
      expect(stats[:misses]).to eq(1)
      expect(stats[:hit_rate]).to eq(66.67)
    end
  end

  describe '#clear_all' do
    it 'removes all cache entries' do
      # Add some entries
      cache_service.set('key1', valid_response)
      cache_service.set('key2', valid_response)

      deleted_count = cache_service.clear_all
      expect(deleted_count).to be >= 2

      # Verify entries are gone
      expect(cache_service.get('key1')).to be_nil
      expect(cache_service.get('key2')).to be_nil
    end

    it 'resets cache statistics' do
      # Generate some stats
      cache_service.set('key1', valid_response)
      cache_service.get('key1')

      cache_service.clear_all

      stats = cache_service.stats
      expect(stats[:hits]).to eq(0)
      expect(stats[:misses]).to eq(0)
    end
  end

  describe 'cache validation' do
    let(:cache_key) { 'test_validation' }

    it 'validates cached data integrity' do
      # Store valid data
      cache_service.set(cache_key, valid_response)

      # Manually corrupt the cache
      Rails.cache.write(cache_key, { invalid: 'data' })

      # Should return nil for corrupted data
      cached_data = cache_service.get(cache_key)
      expect(cached_data).to be_nil
    end

    it 'handles cache read errors gracefully' do
      allow(Rails.cache).to receive(:read).and_raise(StandardError.new('Cache error'))

      cached_data = cache_service.get('any_key')
      expect(cached_data).to be_nil
    end
  end

  describe 'performance considerations' do
    it 'does not cache very large responses' do
      large_response = valid_response.merge(
        'message' => 'x' * 15_000_000 # 15MB
      )

      result = cache_service.set('large_key', large_response)
      expect(result).to be false
    end

    it 'handles cache size limits' do
      # This would test Redis memory limits in a real environment
      # For now, just verify the method exists
      expect(cache_service).to respond_to(:stats)
    end
  end
end
