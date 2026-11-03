class ApplicationController < ActionController::Base
  # Require Devise authentication for all protected dashboard pages
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  stale_when_importmap_changes

  # Helper method for resource-level authorization
  # Ensures users can only access their own tasks, agents, executions, and approvals
  # unless they have administrator or auditor privileges.
  helper_method :can_access?

  def can_access?(record)
    current_user&.can_access?(record)
  end

  def authorize_record_access!(record)
    unless can_access?(record)
      flash[:alert] = "Access Denied: You do not have authorization to view or manage this resource."
      redirect_to root_path and return
    end
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[name role])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name role])
  end
end
