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

  # Governance Dashboard Routes
  get "governance", to: "governance#index", as: :governance
  post "governance/run_evaluations", to: "governance#run_evaluations", as: :run_governance_evaluations
  post "governance/verify_audit", to: "governance#verify_audit", as: :verify_governance_audit

  # Evaluation Center Routes
  get "evaluations", to: "evaluations#index", as: :evaluations
  post "evaluations/run", to: "evaluations#run", as: :run_evaluations

  # MCP Server Management & Marketplace Routes
  resources :mcp_servers do
    member do
      post :connect
      post :disconnect
      post :discover_tools
      patch :toggle_enabled
    end
    resources :mcp_tools, only: [:update] do
      member do
        patch :toggle
      end
    end
  end
end
