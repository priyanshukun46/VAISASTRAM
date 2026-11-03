module Ai
  class Response
    attr_reader :raw_content, :data, :provider, :model, :duration_ms, :fallback_used, :metadata

    def initialize(raw_content:, data:, provider:, model:, duration_ms:, fallback_used: false, metadata: {})
      @raw_content = raw_content
      @data = data || {}
      @provider = provider.to_s
      @model = model.to_s
      @duration_ms = duration_ms.to_f.round(2)
      @fallback_used = fallback_used
      @metadata = metadata || {}
    end

    def success?
      true
    end

    def fallback?
      @fallback_used
    end

    def [](key)
      @data[key.to_s] || @data[key.to_sym]
    end

    def dig(*keys)
      # Support both string and symbol keys
      curr = @data
      keys.each do |k|
        return nil unless curr.is_a?(Hash)
        curr = curr[k.to_s] || curr[k.to_sym]
      end
      curr
    end

    def to_h
      {
        provider: @provider,
        model: @model,
        duration_ms: @duration_ms,
        fallback_used: @fallback_used,
        data: @data,
        metadata: @metadata
      }
    end
  end
end
