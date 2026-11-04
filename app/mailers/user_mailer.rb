class UserMailer < Devise::Mailer
  layout "mailer"

  def welcome_email(user, **_kwargs)
    @user = user
    @notification_type = "welcome_email"
    @idempotency_key = "UserMailer:welcome_email:#{@user.id}"
    mail(to: @user.email, subject: "Welcome to VAISASTRAM Governance Platform")
  end

  def email_verification(user, token = nil, **_kwargs)
    @user = user
    @token = token || @user.email_verification_token || @user.generate_email_verification_token!
    @notification_type = "email_verification"
    @idempotency_key = "UserMailer:email_verification:#{@user.id}:#{@token}"
    mail(to: @user.email, subject: "Verify your VAISASTRAM account email")
  end

  def password_reset(user, token = nil, **_kwargs)
    @user = user
    @token = token
    @notification_type = "password_reset"
    @idempotency_key = "UserMailer:password_reset:#{@user.id}:#{@token}"
    mail(to: @user.email, subject: "Reset your VAISASTRAM password")
  end

  def reset_password_instructions(record, token, opts = {})
    @token = token
    @user = record
    @notification_type = "password_reset"
    @idempotency_key = "UserMailer:password_reset:#{@user.id}:#{@token}"
    devise_mail(record, :reset_password_instructions, opts.merge(subject: "Reset your VAISASTRAM password"))
  end

  def account_security_notification(user, details = {}, **_kwargs)
    @user = user
    @details = details.is_a?(Hash) ? details : { event: details.to_s }
    @notification_type = "account_security_notification"
    @idempotency_key = "UserMailer:account_security_notification:#{@user.id}:#{Digest::SHA256.hexdigest(@details.to_json)}"
    mail(to: @user.email, subject: "Security Alert: Important activity on your VAISASTRAM account")
  end
end
