# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_04_014802) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_steps", force: :cascade do |t|
    t.bigint "execution_id", null: false
    t.integer "position", null: false
    t.string "action_key", null: false
    t.jsonb "arguments", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "risk_level", default: "unknown", null: false
    t.string "policy_decision"
    t.jsonb "result", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_key"], name: "index_agent_steps_on_action_key"
    t.index ["execution_id", "position"], name: "index_agent_steps_on_execution_and_position", unique: true
    t.index ["execution_id"], name: "index_agent_steps_on_execution_id"
    t.index ["risk_level"], name: "index_agent_steps_on_risk_level"
    t.index ["status"], name: "index_agent_steps_on_status"
    t.check_constraint "policy_decision IS NULL OR (policy_decision::text = ANY (ARRAY['allow'::character varying, 'deny'::character varying, 'require_approval'::character varying]::text[]))", name: "check_agent_steps_policy_decision"
    t.check_constraint "risk_level::text = ANY (ARRAY['unknown'::character varying, 'low'::character varying, 'medium'::character varying, 'high'::character varying, 'critical'::character varying]::text[])", name: "check_agent_steps_risk_level"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'evaluating_policy'::character varying, 'waiting_approval'::character varying, 'approved'::character varying, 'rejected'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'blocked'::character varying]::text[])", name: "check_agent_steps_status"
  end

  create_table "agents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "active", null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_agents_on_name"
    t.index ["status"], name: "index_agents_on_status"
    t.index ["user_id"], name: "index_agents_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'paused'::character varying, 'archived'::character varying]::text[])", name: "check_agents_status"
  end

  create_table "approvals", force: :cascade do |t|
    t.bigint "agent_step_id"
    t.bigint "reviewer_id"
    t.string "status", default: "pending", null: false
    t.string "action_digest", null: false
    t.datetime "expires_at"
    t.datetime "reviewed_at"
    t.text "rejection_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "task_id"
    t.bigint "execution_id"
    t.string "tool_name"
    t.jsonb "action_arguments", default: {}, null: false
    t.string "action_fingerprint"
    t.string "policy_decision_reference"
    t.datetime "requested_at"
    t.index ["action_digest"], name: "index_approvals_on_action_digest"
    t.index ["action_fingerprint"], name: "index_approvals_on_action_fingerprint"
    t.index ["agent_step_id"], name: "index_approvals_on_agent_step_id"
    t.index ["execution_id"], name: "index_approvals_on_execution_id"
    t.index ["expires_at"], name: "index_approvals_on_expires_at"
    t.index ["reviewer_id"], name: "index_approvals_on_reviewer_id"
    t.index ["status", "expires_at"], name: "index_approvals_on_status_and_expires_at"
    t.index ["status"], name: "index_approvals_on_status"
    t.index ["task_id"], name: "index_approvals_on_task_id"
    t.index ["tool_name"], name: "index_approvals_on_tool_name"
    t.index ["user_id"], name: "index_approvals_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'expired'::character varying::text, 'invalidated'::character varying::text, 'executed'::character varying::text, 'failed'::character varying::text])", name: "check_approvals_status"
  end

  create_table "audit_events", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "execution_id"
    t.bigint "agent_step_id"
    t.bigint "approval_id"
    t.string "event_type", null: false
    t.string "actor_type", default: "system", null: false
    t.string "actor_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "task_id"
    t.string "tool_name"
    t.string "action_fingerprint"
    t.string "policy_decision"
    t.string "status"
    t.string "chain_id"
    t.integer "sequence_number"
    t.string "prev_event_hash"
    t.string "event_hash"
    t.string "hash_version", default: "v1"
    t.index ["action_fingerprint"], name: "index_audit_events_on_action_fingerprint"
    t.index ["agent_step_id"], name: "index_audit_events_on_agent_step_id"
    t.index ["approval_id"], name: "index_audit_events_on_approval_id"
    t.index ["chain_id", "sequence_number"], name: "index_audit_events_on_chain_id_and_sequence_number"
    t.index ["chain_id"], name: "index_audit_events_on_chain_id"
    t.index ["event_hash"], name: "index_audit_events_on_event_hash"
    t.index ["event_type"], name: "index_audit_events_on_event_type"
    t.index ["execution_id", "occurred_at"], name: "index_audit_events_on_execution_and_occurred_at"
    t.index ["execution_id"], name: "index_audit_events_on_execution_id"
    t.index ["occurred_at"], name: "index_audit_events_on_occurred_at"
    t.index ["policy_decision"], name: "index_audit_events_on_policy_decision"
    t.index ["status"], name: "index_audit_events_on_status"
    t.index ["task_id", "occurred_at"], name: "index_audit_events_on_task_id_and_occurred_at"
    t.index ["task_id"], name: "index_audit_events_on_task_id"
    t.index ["tool_name"], name: "index_audit_events_on_tool_name"
    t.index ["user_id"], name: "index_audit_events_on_user_id"
    t.check_constraint "actor_type::text = ANY (ARRAY['user'::character varying, 'agent'::character varying, 'policy_engine'::character varying, 'system'::character varying]::text[])", name: "check_audit_events_actor_type"
  end

  create_table "executions", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "agent_id", null: false
    t.string "status", default: "pending", null: false
    t.string "provider", default: "gemini", null: false
    t.string "ai_model", default: "gemini-2.5-pro", null: false
    t.jsonb "plan", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "inference_duration"
    t.boolean "fallback_used", default: false, null: false
    t.text "fallback_reason"
    t.integer "retry_count", default: 0, null: false
    t.index ["agent_id"], name: "index_executions_on_agent_id"
    t.index ["ai_model"], name: "index_executions_on_ai_model"
    t.index ["provider"], name: "index_executions_on_provider"
    t.index ["status"], name: "index_executions_on_status"
    t.index ["task_id"], name: "index_executions_on_task_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'planning'::character varying, 'planned'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'paused'::character varying, 'blocked'::character varying]::text[])", name: "check_executions_status"
  end

  create_table "policies", force: :cascade do |t|
    t.bigint "user_id"
    t.string "name", null: false
    t.text "description"
    t.string "action_key", null: false
    t.string "effect", default: "deny", null: false
    t.jsonb "conditions", default: {}, null: false
    t.integer "priority", default: 100, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_key", "priority"], name: "index_policies_on_action_key_and_priority"
    t.index ["action_key"], name: "index_policies_on_action_key"
    t.index ["enabled"], name: "index_policies_on_enabled"
    t.index ["priority"], name: "index_policies_on_priority"
    t.index ["user_id"], name: "index_policies_on_user_id"
    t.check_constraint "effect::text = ANY (ARRAY['allow'::character varying, 'deny'::character varying, 'require_approval'::character varying]::text[])", name: "check_policies_effect"
  end

  create_table "tasks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "agent_id", null: false
    t.string "title", null: false
    t.text "instruction", null: false
    t.string "status", default: "pending", null: false
    t.datetime "submitted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_tasks_on_agent_id"
    t.index ["status"], name: "index_tasks_on_status"
    t.index ["submitted_at"], name: "index_tasks_on_submitted_at"
    t.index ["user_id"], name: "index_tasks_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'planning'::character varying, 'planned'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'blocked'::character varying]::text[])", name: "check_tasks_status"
  end

  create_table "tools", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.jsonb "input_schema", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.string "risk_level", default: "low", null: false
    t.string "required_permission"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_tools_on_enabled"
    t.index ["key"], name: "index_tools_on_key", unique: true
    t.check_constraint "risk_level::text = ANY (ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying, 'critical'::character varying]::text[])", name: "check_tools_risk_level"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", default: "Operator", null: false
    t.string "role", default: "operator", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "agent_steps", "executions", on_delete: :cascade
  add_foreign_key "agents", "users", on_delete: :cascade
  add_foreign_key "approvals", "agent_steps", on_delete: :cascade
  add_foreign_key "approvals", "executions", on_delete: :cascade
  add_foreign_key "approvals", "tasks", on_delete: :cascade
  add_foreign_key "approvals", "users", column: "reviewer_id", on_delete: :nullify
  add_foreign_key "approvals", "users", on_delete: :nullify
  add_foreign_key "audit_events", "agent_steps", on_delete: :nullify
  add_foreign_key "audit_events", "approvals", on_delete: :nullify
  add_foreign_key "audit_events", "executions", on_delete: :nullify
  add_foreign_key "audit_events", "tasks", on_delete: :nullify
  add_foreign_key "audit_events", "users", on_delete: :nullify
  add_foreign_key "executions", "agents", on_delete: :cascade
  add_foreign_key "executions", "tasks", on_delete: :cascade
  add_foreign_key "policies", "users", on_delete: :nullify
  add_foreign_key "tasks", "agents", on_delete: :cascade
  add_foreign_key "tasks", "users", on_delete: :cascade
end
