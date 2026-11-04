class McpServer < ApplicationRecord
  TRANSPORT_TYPES = %w[stdio streamable_http].freeze
  STATUSES = %w[disconnected connecting connected failed disabled].freeze

  ALLOWED_STDIO_COMMANDS = %w[
    npx node python python3 ruby uvx deno bun wordcraft
  ].freeze

  DISALLOWED_COMMANDS = %w[
    sh bash zsh ksh csh fish dash powershell cmd.exe
    sudo su rm rmdir curl wget nc netcat ncat socat
    chmod chown chgrp eval exec system
  ].freeze

  belongs_to :user, optional: true
  has_many :mcp_tools, dependent: :destroy

  encrypts :environment_variables
  encrypts :authentication_configuration

  before_validation :generate_identifier_if_missing
  before_validation :normalize_arguments
  before_save :track_configuration_changes

  validates :name, presence: true, length: { maximum: 100 }
  validates :server_identifier, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9_-]+\z/, message: "must contain only lowercase letters, numbers, hyphens, and underscores" }
  validates :transport_type, presence: true, inclusion: { in: TRANSPORT_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :connection_timeout, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 }
  validates :request_timeout, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 300 }

  validate :validate_stdio_configuration, if: :stdio?
  validate :validate_streamable_http_configuration, if: :streamable_http?

  after_save :sync_tools_state_if_enabled_changed

  scope :enabled, -> { where(enabled: true) }
  scope :connected, -> { where(status: "connected") }
  scope :stdio_servers, -> { where(transport_type: "stdio") }
  scope :http_servers, -> { where(transport_type: "streamable_http") }

  def stdio?
    transport_type == "stdio"
  end

  def streamable_http?
    transport_type == "streamable_http"
  end

  def connected?
    status == "connected"
  end

  def disabled?
    !enabled? || status == "disabled"
  end

  # Returns environment variables as a sanitized Hash of strings
  def env_hash
    raw = environment_variables.to_s.strip
    return {} if raw.blank?

    begin
      parsed = JSON.parse(raw)
      return parsed.transform_keys(&:to_s).transform_values(&:to_s) if parsed.is_a?(Hash)
    rescue JSON::ParserError
      # Support line-delimited KEY=VALUE format
      result = {}
      raw.each_line do |line|
        line = line.strip
        next if line.blank? || line.start_with?("#")
        key, val = line.split("=", 2)
        result[key.strip] = val.to_s.strip if key.present?
      end
      result
    end
  end

  # Returns authentication headers as a Hash for HTTP transport
  def auth_headers
    raw = authentication_configuration.to_s.strip
    return {} if raw.blank?

    begin
      parsed = JSON.parse(raw)
      if parsed.is_a?(Hash)
        headers = {}
        if parsed["bearer_token"].present?
          headers["Authorization"] = "Bearer #{parsed['bearer_token']}"
        elsif parsed["api_key"].present?
          header_name = parsed["header_name"].presence || "X-API-Key"
          headers[header_name] = parsed["api_key"].to_s
        end
        if parsed["headers"].is_a?(Hash)
          headers.merge!(parsed["headers"])
        end
        return headers
      end
    rescue JSON::ParserError
      # Raw token fallback: treat plain string as Bearer token
      return { "Authorization" => "Bearer #{raw}" }
    end

    {}
  end

  def args_array
    Array(arguments).map(&:to_s)
  end

  private

  def generate_identifier_if_missing
    if server_identifier.blank? && name.present?
      slug = name.to_s.downcase.strip.gsub(/[^a-z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
      self.server_identifier = slug.presence || "mcp_#{SecureRandom.hex(4)}"
    end
  end

  def normalize_arguments
    if arguments.is_a?(String) && arguments.strip.start_with?("[")
      begin
        parsed = JSON.parse(arguments)
        self.arguments = parsed if parsed.is_a?(Array)
      rescue JSON::ParserError
        # Keep raw string so validation rejects non-array input
      end
    elsif arguments.nil?
      self.arguments = []
    end
  end

  def validate_stdio_configuration
    if command.blank?
      errors.add(:command, "cannot be blank for STDIO transport")
      return
    end

    cmd_base = File.basename(command.to_s.strip).downcase

    if DISALLOWED_COMMANDS.include?(cmd_base)
      errors.add(:command, "'#{cmd_base}' is an explicitly prohibited shell or administrative executable")
      return
    end

    if command.to_s.include?("..")
      errors.add(:command, "path traversal sequences ('..') are strictly prohibited")
      return
    end

    # Must match allowed command list or be in allowed directory
    unless ALLOWED_STDIO_COMMANDS.include?(cmd_base) || allowed_custom_executable?(command)
      errors.add(:command, "'#{cmd_base}' is not in the allowlist of permitted MCP executables (#{ALLOWED_STDIO_COMMANDS.join(', ')})")
    end

    unless arguments.is_a?(Array)
      errors.add(:arguments, "must be an array of argument strings")
    end
  end

  def allowed_custom_executable?(cmd)
    # Allows safe absolute executable paths if configured in Rails credentials / env
    custom_allowed = ENV["MCP_ALLOWED_EXECUTABLES"].to_s.split(",").map(&:strip)
    custom_allowed.include?(cmd.to_s.strip)
  end

  def validate_streamable_http_configuration
    if endpoint_url.blank?
      errors.add(:endpoint_url, "cannot be blank for Streamable HTTP transport")
      return
    end

    begin
      uri = URI.parse(endpoint_url)
      unless %w[http https].include?(uri.scheme&.downcase)
        errors.add(:endpoint_url, "must use http or https protocol")
        return
      end

      # Unless local connections are explicitly allowed by admin, require HTTPS and non-private IP
      if uri.scheme.downcase == "http" && !allow_local_connections? && !Rails.env.test?
        errors.add(:endpoint_url, "must use secure HTTPS for remote endpoints")
        return
      end

      # Validate host and SSRF protection
      ssrf_check = Mcp::Security::SsrfGuard.check(endpoint_url, allow_local: allow_local_connections?)
      unless ssrf_check.safe?
        errors.add(:endpoint_url, "violates SSRF security policy: #{ssrf_check.reason}")
      end
    rescue URI::InvalidURIError => e
      errors.add(:endpoint_url, "is not a valid URL: #{e.message}")
    end
  end

  def track_configuration_changes
    tracked_fields = %w[command arguments endpoint_url environment_variables authentication_configuration transport_type]
    if (changes.keys & tracked_fields).any? && persisted?
      self.configuration_version += 1
    end
  end

  def sync_tools_state_if_enabled_changed
    if saved_change_to_enabled?
      mcp_tools.find_each(&:sync_with_tool_registry)
    end
  end
end
