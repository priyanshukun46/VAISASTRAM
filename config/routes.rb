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

  # Human-in-the-Loop Approval Center
  resources :approvals, only: [:index, :show] do
    member do
      patch :approve
      post :approve
      patch :reject
      post :reject
    end
  end

  get "policies", to: "policies#index", as: :policies
  patch "policies/:id/toggle", to: "policies#toggle", as: :toggle_policy

  # Audit Center Routes
  get "audit", to: "audit#index", as: :audit
  post "audit/verify", to: "audit#verify", as: :verify_audit

  # Execution Timeline & Replay Routes
  resources :executions, only: [:show] do
    member do
      get :timeline
      get :audit
      get :replay
      post :replay
    end
  end

  get "evaluations", to: "evaluations#index", as: :evaluations
end
