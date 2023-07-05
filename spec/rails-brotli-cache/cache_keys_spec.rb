# frozen_string_literal: true

require 'spec_helper'

return unless ENV['RAILS_CACHE_STORE'] == 'redis_cache_store'

describe RailsBrotliCache do
  class Post
    include ActiveModel::Model

    attr_accessor :id

    def to_param
      "post/#{id}"
    end
  end

  let(:redis_store) do
    ActiveSupport::Cache::RedisCacheStore.new(redis: $redis)
  end

  let(:brotli_store) do
    RailsBrotliCache::Store.new(
      redis_store
    )
  end

  describe "generated cache keys are identical to standard cache stores" do
    it "works for string keys" do
      redis_store.fetch("string-key") { 123 }
      brotli_store.fetch("string-key") { 123 }
      expect($redis.get("br-string-key")).to be_present
      expect($redis.get("string-key")).to be_present
    end

    it "ActiveModel object keys" do
      post_1 = Post.new(id: 1)
      redis_store.fetch(post_1) { 123 }
      brotli_store.fetch(post_1) { 123 }
      expect($redis.get("br-post/1")).to be_present
      expect($redis.get("post/1")).to be_present
    end

    it "ActiveModel objects complex collection keys" do
      post_1 = Post.new(id: 1)
      post_2 = Post.new(id: 2)
      collection = [post_1, post_2]
      redis_store.fetch([:views, "controller/action", collection]) { 123 }
      brotli_store.fetch([:views, "controller/action", collection]) { 123 }
      expect($redis.get("views/controller/action/post/1/post/2")).to be_present
      expect($redis.get("br-views/controller/action/post/1/post/2")).to be_present
    end
  end
end
