Rails.application.routes.draw do
  # Devise Authentication
  devise_for :users

  # Convenience & legacy route redirects
  get "/session/new", to: redirect("/users/sign_in")
  get "/login", to: redirect("/users/sign_in")
  get "/sign_in", to: redirect("/users/sign_in")
  get "/sign_up", to: redirect("/users/sign_up")
  get "/register", to: redirect("/users/sign_up")

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Core Governance Routes
  root "dashboard#index"
  get "dashboard", to: "dashboard#index", as: :dashboard

  # Protected navigation routes
  get "workspace", to: "workspace#index", as: :workspace
  post "workspace", to: "workspace#create"
  get "approvals", to: "approvals#index", as: :approvals
  get "policies", to: "policies#index", as: :policies
  get "audit", to: "audit#index", as: :audit
  get "evaluations", to: "evaluations#index", as: :evaluations
end
