class UserMailerPreview < ActionMailer::Preview
  def welcome_email
    user = User.first || User.new(name: "Ada Lovelace", email: "ada@example.com", role: "operator")
    UserMailer.welcome_email(user)
  end

  def email_verification
    user = User.first || User.new(name: "Ada Lovelace", email: "ada@example.com", role: "operator")
    UserMailer.email_verification(user, "preview_verification_token_12345")
  end

  def password_reset
    user = User.first || User.new(name: "Ada Lovelace", email: "ada@example.com", role: "operator")
    UserMailer.password_reset(user, "preview_reset_token_67890")
  end

  def account_security_notification
    user = User.first || User.new(name: "Ada Lovelace", email: "ada@example.com", role: "operator")
    UserMailer.account_security_notification(user, {
      event: "New sign-in from unverified IP address",
      ip_address: "198.51.100.42"
    })
  end
end
