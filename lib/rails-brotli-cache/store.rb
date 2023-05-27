# frozen_string_literal: true

require 'active_support/cache'
require 'brotli'

module RailsBrotliCache
  class Store < ::ActiveSupport::Cache::Store
    COMPRESS_THRESHOLD = ENV.fetch("BR_CACHE_COMPRESS_THRESHOLD", 1).to_f * 1024.0
    BR_COMPRESS_QUALITY = ENV.fetch("BR_CACHE_COMPRESS_QUALITY", 5).to_i
    MARK_BR_COMPRESSED = "\x02".b

    attr_reader :core_store

    def initialize(core_store, options = {})
      @core_store = core_store
      @prefix = if options.key?(:prefix)
        options.fetch(:prefix)
      else
        "br-"
      end

      @compressor_class = compressor_class(options, default: BrotliCompressor)
    end

    def fetch(name, options = nil, &block)
      value = read(name, options)

      if value.present? && !options&.fetch(:force, false) == true
        return value
      end

      if block_given?
        value = block.call
        write(name, value, options)

        value
      elsif options && options[:force]
        raise ArgumentError, "Missing block: Calling `Cache#fetch` with `force: true` requires a block."
      else
        read(name, options)
      end
    end

    def write(name, value, options = nil)
      if value.is_a?(Integer)
        return @core_store.write(
          cache_key(name),
          value
        )
      end

      options = (options || {}).reverse_merge(compress: true)
      payload = compressed(value, options)

      @core_store.write(
        cache_key(name),
        payload,
        options.merge(compress: false)
      )
    end

    def read(name, options = nil)
      payload = @core_store.read(
        cache_key(name),
        options
      )

      uncompressed(payload)
    end

    def write_multi(hash, options = nil)
      new_hash = hash.map do |key, val|
        [
          cache_key(key),
          compressed(val, options)
        ]
      end

      @core_store.write_multi(new_hash, options)
    end

    def read_multi(*names)
      options = names.extract_options!
      names = names.map { |name| cache_key(name) }

      Hash[core_store.read_multi(*names, options).map do |key, val|
        [source_cache_key(key), uncompressed(val)]
      end]
    end

    def fetch_multi(*names)
      options = names.extract_options!
      names = names.map { |name| cache_key(name) }

      @core_store.fetch_multi(*names, options) do |name|
        compressed(yield(name), options)
      end
    end

    def exist?(name, options = nil)
      @core_store.exist?(cache_key(name), options)
    end

    def delete(name, options = nil)
      @core_store.delete(cache_key(name), options)
    end

    def clear(options = nil)
      @core_store.clear
    end

    def increment(*args)
      args[0] = cache_key(args[0])
      @core_store.increment(*args)
    end

    def decrement(*args)
      args[0] = cache_key(args[0])
      @core_store.decrement(*args)
    end

    def self.supports_cache_versioning?
      true
    end

    private

    def compressed(value, options)
      options ||= {}
      serialized = Marshal.dump(value)

      if serialized.bytesize >= COMPRESS_THRESHOLD && !options.fetch(:compress) == false
        compressor = compressor_class(options, default: @compressor_class)
        compressed_payload = compressor.deflate(serialized)
        if compressed_payload.bytesize < serialized.bytesize
          MARK_BR_COMPRESSED + compressed_payload
        else
          serialized
        end
      else
        serialized
      end
    end

    def uncompressed(payload)
      return nil unless payload.present?

      return payload if payload.is_a?(Integer)

      serialized = if payload.start_with?(MARK_BR_COMPRESSED)
        compressor = compressor_class(options, default: @compressor_class)
        compressor.inflate(payload.byteslice(1..-1))
      else
        payload
      end

      Marshal.load(serialized)
    end

    def compressor_class(options, default:)
      options = options || {}
      if (klass = options[:compressor_class])
        klass
      else
        default
      end
    end

    def cache_key(name)
      "#{@prefix}#{name}"
    end

    def source_cache_key(name)
      name.remove(@prefix)
    end

    class BrotliCompressor
      def self.deflate(payload)
        ::Brotli.deflate(payload, quality: BR_COMPRESS_QUALITY)
      end

      def self.inflate(payload)
        ::Brotli.inflate(payload)
      end
    end
  end
end
