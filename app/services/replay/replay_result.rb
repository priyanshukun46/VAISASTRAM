module Replay
  class ReplayResult
    attr_reader :mode, :session_id, :execution_id, :task_id, :reconstructed_status,
                :reconstructed_plan, :reconstructed_steps, :simulated_steps,
                :differences, :audit_events_count, :hash_chain_valid,
                :verification_report, :created_at

    def initialize(
      mode:,
      session_id:,
      execution_id:,
      task_id:,
      reconstructed_status:,
      reconstructed_plan: {},
      reconstructed_steps: [],
      simulated_steps: [],
      differences: [],
      audit_events_count: 0,
      hash_chain_valid: true,
      verification_report: nil
    )
      @mode = mode.to_s
      @session_id = session_id
      @execution_id = execution_id
      @task_id = task_id
      @reconstructed_status = reconstructed_status
      @reconstructed_plan = reconstructed_plan || {}
      @reconstructed_steps = reconstructed_steps || []
      @simulated_steps = simulated_steps || []
      @differences = differences || []
      @audit_events_count = audit_events_count
      @hash_chain_valid = hash_chain_valid
      @verification_report = verification_report
      @created_at = Time.current
    end

    def inspection?
      @mode == "inspection"
    end

    def simulation?
      @mode == "simulation"
    end

    def divergent?
      @differences.any?
    end

    def verified?
      @hash_chain_valid
    end
  end
end
