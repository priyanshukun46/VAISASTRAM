module Replay
  class ReplayContext
    attr_reader :execution, :task, :user, :mode, :session_id, :events, :steps, :created_at

    def initialize(execution:, user:, mode: :inspection)
      @execution = execution
      @task = execution.task
      @user = user
      @mode = mode.to_sym
      @session_id = "replay_#{@mode}_#{SecureRandom.hex(8)}"
      @created_at = Time.current

      # Eager load chronological events for this execution
      @events = AuditEvent.for_execution(execution.id).chronological.to_a
      @steps = execution.agent_steps.order(position: :asc).to_a
    end

    def inspection?
      @mode == :inspection
    end

    def simulation?
      @mode == :simulation
    end
  end
end
