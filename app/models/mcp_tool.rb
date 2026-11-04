class McpTool < ApplicationRecord
  RISK_LEVELS = %w[low medium high critical].freeze
  POLICY_DECISIONS = %w[allow require_approval deny].freeze

  BUILT_IN_TOOL_KEYS = %w[
    lookup_invoice verify_invoice retrieve_invoice get_vendor prepare_payment
  ].freeze

  belongs_to :mcp_server

  before_validation :generate_namespaced_key_and_schema_hash

  validates :external_tool_name, presence: true,
            format: { with: /\A[a-zA-Z0-9_-]+\z/, message: "must contain only alphanumeric characters, underscores, and hyphens" }
  validates :namespaced_tool_key, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9_.]+\z/, message: "must contain only lowercase letters, numbers, underscores, and dots" }
  validates :schema_hash, presence: true
  validates :risk_classification, presence: true, inclusion: { in: RISK_LEVELS }
  validates :policy_decision, presence: true, inclusion: { in: POLICY_DECISIONS }
  validate :prevent_builtin_tool_collision

  after_save :sync_with_tool_registry
  after_destroy :cleanup_tool_registry

  scope :enabled, -> { where(enabled: true) }
  scope :requiring_approval, -> { where(policy_decision: "require_approval") }

  def self.canonicalize_schema(schema)
    return {} unless schema.is_a?(Hash)

    schema.each_with_object({}) do |(k, v), h|
      h[k.to_s] = v.is_a?(Hash) ? canonicalize_schema(v) : (v.is_a?(Array) ? v.map { |i| i.is_a?(Hash) ? canonicalize_schema(i) : i } : v)
    end.sort.to_h
  end

  def self.compute_schema_hash(schema)
    canonical = canonicalize_schema(schema)
    Digest::SHA256.hexdigest(canonical.to_json)
  end

  def sync_with_tool_registry
    tool_record = Tool.find_or_initialize_by(key: namespaced_tool_key)

    is_active = enabled? && mcp_server.enabled? && mcp_server.connected?
    tool_record.assign_attributes(
      name: "#{mcp_server.name} — #{external_tool_name.humanize}",
      description: description.presence || "Discovered MCP tool from #{mcp_server.name}",
      input_schema: input_schema || {},
      risk_level: risk_classification,
      enabled: is_active
    )
    tool_record.save!
  end

  private

  def generate_namespaced_key_and_schema_hash
    if mcp_server.present? && external_tool_name.present?
      server_id = mcp_server.server_identifier.to_s.downcase.strip
      tool_id = external_tool_name.to_s.downcase.strip.gsub(/[^a-z0-9_]+/, "_")
      self.namespaced_tool_key = "mcp.#{server_id}.#{tool_id}"
    end

    if schema_hash.blank? || input_schema_changed?
      self.schema_hash = self.class.compute_schema_hash(input_schema)
    end
  end

  def prevent_builtin_tool_collision
    clean_name = external_tool_name.to_s.strip.downcase
    if BUILT_IN_TOOL_KEYS.include?(clean_name) || BUILT_IN_TOOL_KEYS.include?(namespaced_tool_key)
      errors.add(:external_tool_name, "'#{external_tool_name}' collides with a core built-in VAISASTRAM tool and cannot be overridden")
    end
  end

  def cleanup_tool_registry
    Tool.where(key: namespaced_tool_key).destroy_all
  end
end
