require "digest"

module Policies
  class Fingerprint
    SENSITIVE_ARGUMENT_KEYS = %w[
      api_key apiKey secret token password authorization auth_token private_key credential
    ].freeze

    def self.generate(user:, task:, action_key:, arguments:, resource_id: nil)
      canonical_args = canonicalize_arguments(arguments)
      res_id = resource_id || extract_resource_id(arguments)

      # Deterministic, order-independent canonical payload
      payload = {
        user_id: user&.id,
        task_id: task&.id,
        action: action_key.to_s.strip.downcase,
        resource_id: res_id.to_s.strip,
        arguments: canonical_args
      }

      Digest::SHA256.hexdigest(canonical_json(payload))
    end

    def self.canonicalize_arguments(args)
      return {} if args.blank? || !args.is_a?(Hash)

      args.each_with_object({}) do |(key, value), clean_hash|
        key_str = key.to_s.strip.downcase
        next if SENSITIVE_ARGUMENT_KEYS.include?(key_str)

        clean_hash[key.to_s] = canonicalize_value(value)
      end.sort.to_h
    end

    def self.extract_resource_id(args)
      return nil unless args.is_a?(Hash)

      args["invoice_id"] || args[:invoice_id] ||
        args["vendor_id"] || args[:vendor_id] ||
        args["account_id"] || args[:account_id] ||
        args["target"] || args[:target] ||
        args["resource_id"] || args[:resource_id]
    end

    private_class_method def self.canonicalize_value(val)
      case val
      when Hash
        canonicalize_arguments(val)
      when Array
        val.map { |v| canonicalize_value(v) }
      when Numeric, TrueClass, FalseClass, NilClass
        val
      else
        val.to_s.strip
      end
    end

    private_class_method def self.canonical_json(object)
      case object
      when Hash
        "{" + object.sort.map { |k, v| "#{k.to_s.to_json}:#{canonical_json(v)}" }.join(",") + "}"
      when Array
        "[" + object.map { |v| canonical_json(v) }.join(",") + "]"
      else
        object.to_json
      end
    end
  end
end
