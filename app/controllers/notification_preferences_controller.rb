class NotificationPreferencesController < ApplicationController
  before_action :authenticate_user!, except: [:verify_email]

  def show
    @preferences = current_user.notification_preferences
    @recent_notifications = AuditEvent
      .where(user_id: current_user.id, event_type: %w[notification_sent notification_failed notification_skipped notification_queued])
      .order(occurred_at: :desc)
      .limit(50)

    @stats = {
      total: @recent_notifications.size,
      delivered: @recent_notifications.count { |n| n.status == "delivered" },
      failed: @recent_notifications.count { |n| n.status == "failed" },
      skipped: @recent_notifications.count { |n| n.status == "skipped" }
    }
  end

  def update
    permitted = params.fetch(:preferences, {}).permit(
      :approval_requests,
      :execution_updates,
      :security_alerts,
      :account_notifications
    )

    new_prefs = {
      "approval_requests"     => permitted[:approval_requests] == "1" || permitted[:approval_requests] == "true",
      "execution_updates"     => permitted[:execution_updates] == "1" || permitted[:execution_updates] == "true",
      "security_alerts"       => permitted[:security_alerts] == "1" || permitted[:security_alerts] == "true",
      "account_notifications" => permitted[:account_notifications] == "1" || permitted[:account_notifications] == "true"
    }

    current_user.update!(notification_preferences: new_prefs)

    Audit::Recorder.record(
      event_type: "notification_preference_updated",
      actor_type: "user",
      actor_id: current_user.id.to_s,
      user: current_user,
      metadata: { preferences: new_prefs }
    )

    respond_to do |format|
      format.html { redirect_to notification_preferences_path, notice: "Notification preferences updated successfully." }
      format.turbo_stream {
        flash.now[:notice] = "Notification preferences updated successfully."
        render turbo_stream: [
          turbo_stream.replace("flash-messages", partial: "shared/flash"),
          turbo_stream.replace("preferences-form", partial: "notification_preferences/form", locals: { preferences: current_user.notification_preferences })
        ]
      }
    end
  end

  def send_test_email
    UserMailer.welcome_email(current_user).deliver_later

    respond_to do |format|
      format.html { redirect_to notification_preferences_path, notice: "Test notification enqueued via Active Job / Solid Queue." }
      format.turbo_stream {
        flash.now[:notice] = "Test notification enqueued via Active Job / Solid Queue."
        render turbo_stream: turbo_stream.replace("flash-messages", partial: "shared/flash")
      }
    end
  end

  def verify_email
    token = params[:token]
    user = current_user || User.find_by(email_verification_token: token)

    if user && token.present? && user.verify_email!(token)
      redirect_to(user_signed_in? ? notification_preferences_path : new_user_session_path, notice: "Your email address has been verified successfully.")
    else
      redirect_to(user_signed_in? ? notification_preferences_path : new_user_session_path, alert: "Email verification link is invalid or has expired.")
    end
  end
end
