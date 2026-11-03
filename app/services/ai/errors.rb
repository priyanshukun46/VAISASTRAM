module Ai
  module Errors
    # Base error class for all AI provider integration errors
    class Error < StandardError
      attr_reader :provider, :status_code, :raw_response

      def initialize(message = nil, provider: nil, status_code: nil, raw_response: nil)
        @provider = provider
        @status_code = status_code
        @raw_response = raw_response
        super(message || default_message)
      end

      private

      def default_message
        msg = self.class.name.demodulize.underscore.humanize
        msg += " (#{provider})" if provider
        msg += " [HTTP #{status_code}]" if status_code
        msg
      end
    end

    # Transient errors — ELIGIBLE for fallback to secondary provider
    class TransientError < Error; end
    class TimeoutError < TransientError; end
    class NetworkError < TransientError; end
    class ConnectionRefusedError < NetworkError; end
    class RateLimitError < TransientError; end # HTTP 429
    class ServerError < TransientError; end    # HTTP 500..599

    # Fatal errors — INELIGIBLE for automatic fallback (must fail fast)
    class FatalError < Error; end
    class AuthenticationError < FatalError; end # HTTP 401, 403
    class InvalidRequestError < FatalError; end # HTTP 400
    class ModelNotFoundError < FatalError; end  # HTTP 404
    class ConfigurationError < FatalError; end  # Missing API keys / config
    class CloudFallbackDisabledError < FatalError; end

    # Validation errors — Unparseable or schema-violating output
    class ValidationError < Error; end

    # Exhausted all available providers
    class AllProvidersFailedError < Error
      attr_reader :attempts

      def initialize(message, attempts: [])
        @attempts = attempts
        super(message)
      end
    end
  end

  # Export directly into Ai:: namespace for clean caller syntax (e.g. Ai::TimeoutError)
  Error                      = Errors::Error
  TransientError             = Errors::TransientError
  TimeoutError               = Errors::TimeoutError
  NetworkError               = Errors::NetworkError
  ConnectionRefusedError     = Errors::ConnectionRefusedError
  RateLimitError             = Errors::RateLimitError
  ServerError                = Errors::ServerError
  FatalError                 = Errors::FatalError
  AuthenticationError        = Errors::AuthenticationError
  InvalidRequestError        = Errors::InvalidRequestError
  ModelNotFoundError         = Errors::ModelNotFoundError
  ConfigurationError         = Errors::ConfigurationError
  CloudFallbackDisabledError = Errors::CloudFallbackDisabledError
  ValidationError            = Errors::ValidationError
  AllProvidersFailedError    = Errors::AllProvidersFailedError
end
