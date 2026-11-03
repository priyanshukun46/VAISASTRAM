require "net/http"
require "json"
require "uri"

module Ai
  class BaseProvider
    DEFAULT_TIMEOUT_SECONDS = 30

    attr_reader :api_key, :model, :timeout

    def initialize(api_key: nil, model: nil, timeout: nil)
      @api_key = api_key || default_api_key
      @model = model || default_model
      @timeout = (timeout || default_timeout).to_i
    end

    def provider_name
      raise NotImplementedError, "#{self.class.name} must implement #provider_name"
    end

    def generate(prompt, options = {})
      validate_configuration!

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = execute_http_request(prompt, options)
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0

      parse_provider_response(response, duration_ms: duration_ms)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Ai::TimeoutError.new("Request to #{provider_name} timed out after #{@timeout}s: #{e.message}", provider: provider_name)
    rescue Errno::ECONNREFUSED => e
      raise Ai::ConnectionRefusedError.new("Connection refused to #{provider_name}: #{e.message}", provider: provider_name)
    rescue SocketError, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError => e
      raise Ai::NetworkError.new("Network failure connecting to #{provider_name}: #{e.message}", provider: provider_name)
    end

    protected

    def default_api_key
      raise NotImplementedError
    end

    def default_model
      raise NotImplementedError
    end

    def default_timeout
      ENV.fetch("AI_REQUEST_TIMEOUT", DEFAULT_TIMEOUT_SECONDS).to_i
    end

    def validate_configuration!
      if @api_key.blank?
        raise Ai::ConfigurationError.new("Missing API key for #{provider_name}. Please set #{env_key_name}.", provider: provider_name)
      end
    end

    def env_key_name
      "#{provider_name.upcase}_API_KEY"
    end

    def execute_http_request(prompt, options)
      uri = endpoint_uri
      request = build_http_request(uri, prompt, options)
      req_timeout = (options[:timeout] || @timeout).to_i

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = req_timeout
      http.read_timeout = req_timeout
      http.write_timeout = req_timeout

      response = http.request(request)
      handle_http_errors!(response)
      response
    end

    def endpoint_uri
      raise NotImplementedError
    end

    def build_http_request(uri, prompt, options)
      raise NotImplementedError
    end

    def parse_provider_response(response, duration_ms:)
      raise NotImplementedError
    end

    def handle_http_errors!(response)
      code = response.code.to_i
      return if code >= 200 && code < 300

      body = response.body.to_s
      sanitized_body = sanitize_error_body(body)

      case code
      when 401, 403
        raise Ai::AuthenticationError.new("Authentication failed for #{provider_name}: #{sanitized_body}", provider: provider_name, status_code: code, raw_response: body)
      when 400
        raise Ai::InvalidRequestError.new("Invalid request to #{provider_name}: #{sanitized_body}", provider: provider_name, status_code: code, raw_response: body)
      when 404
        raise Ai::ModelNotFoundError.new("Model or endpoint not found on #{provider_name}: #{sanitized_body}", provider: provider_name, status_code: code, raw_response: body)
      when 429
        raise Ai::RateLimitError.new("Rate limit exceeded on #{provider_name} (HTTP 429): #{sanitized_body}", provider: provider_name, status_code: code, raw_response: body)
      when 500..599
        raise Ai::ServerError.new("Upstream server error from #{provider_name} (HTTP #{code}): #{sanitized_body}", provider: provider_name, status_code: code, raw_response: body)
      else
        raise Ai::Error.new("Unexpected HTTP response from #{provider_name} (HTTP #{code}): #{sanitized_body}", provider: provider_name, status_code: code, raw_response: body)
      end
    end

    def sanitize_error_body(body)
      parsed = JSON.parse(body) rescue nil
      if parsed.is_a?(Hash)
        error_val = parsed["error"]
        error_msg = if error_val.is_a?(Hash)
          error_val["message"]
        elsif error_val.is_a?(String)
          error_val
        end || parsed["message"]
        return error_msg.to_s.truncate(200) if error_msg.present?
      end
      body.truncate(200)
    end
  end
end
