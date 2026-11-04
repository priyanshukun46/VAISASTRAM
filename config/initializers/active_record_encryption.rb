# Rails Active Record Encryption Configuration
# Ensures sensitive MCP credentials and environment variables are always encrypted at rest.
Rails.application.configure do
  secret = Rails.application.secret_key_base.presence || "vaisastram-governed-default-secret-key-base-32-bytes"

  config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||
    Rails.application.credentials.dig(:active_record_encryption, :primary_key) ||
    Digest::SHA256.hexdigest("#{secret}:primary")[0..31]

  config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||
    Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) ||
    Digest::SHA256.hexdigest("#{secret}:deterministic")[0..31]

  config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||
    Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) ||
    Digest::SHA256.hexdigest("#{secret}:salt")[0..31]

  # Support migrating unencrypted data safely
  config.active_record.encryption.support_unencrypted_data = true
end
