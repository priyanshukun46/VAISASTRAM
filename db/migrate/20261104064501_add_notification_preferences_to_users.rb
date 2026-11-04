class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notification_preferences, :jsonb, default: {
      "approval_requests" => true,
      "execution_updates" => true,
      "security_alerts" => true,
      "account_notifications" => true
    }, null: false

    add_column :users, :email_verification_token, :string
    add_column :users, :email_verification_sent_at, :datetime
    add_column :users, :email_verified_at, :datetime

    add_index :users, :email_verification_token, unique: true
  end
end
