module Governance
  class QueryScope
    VALID_RANGES = %w[24h 7d 30d all custom].freeze
    DEFAULT_RANGE = "7d".freeze

    attr_reader :user, :range, :start_date, :end_date, :time_window

    def start_time
      @time_window&.begin
    end

    def end_time
      @time_window&.end
    end

    def initialize(user:, range: DEFAULT_RANGE, start_date: nil, end_date: nil)
      @user = user
      @range = VALID_RANGES.include?(range.to_s.downcase) ? range.to_s.downcase : DEFAULT_RANGE
      @start_date = start_date
      @end_date = end_date
      @time_window = calculate_time_window
    end

    def admin_or_auditor?
      user.admin? || user.auditor?
    end

    def tasks
      base = admin_or_auditor? ? Task.all : user.tasks
      @time_window ? base.where(created_at: @time_window) : base
    end

    def executions
      base = admin_or_auditor? ? Execution.all : Execution.where(task_id: tasks_unfiltered.select(:id))
      @time_window ? base.where(created_at: @time_window) : base
    end

    def agent_steps
      base = admin_or_auditor? ? AgentStep.all : AgentStep.where(execution_id: executions_unfiltered.select(:id))
      @time_window ? base.where(created_at: @time_window) : base
    end

    def approvals
      base = if admin_or_auditor?
        Approval.all
      else
        Approval.where("user_id = :uid OR task_id IN (:tids)", uid: user.id, tids: tasks_unfiltered.select(:id))
      end
      @time_window ? base.where(created_at: @time_window) : base
    end

    def audit_events
      base = if admin_or_auditor?
        AuditEvent.all
      else
        AuditEvent.where(
          "user_id = :uid OR task_id IN (:tids) OR execution_id IN (:eids)",
          uid: user.id,
          tids: tasks_unfiltered.select(:id),
          eids: executions_unfiltered.select(:id)
        )
      end
      @time_window ? base.where(occurred_at: @time_window) : base
    end

    def range_label
      case @range
      when "24h" then "Last 24 Hours"
      when "7d" then "Last 7 Days"
      when "30d" then "Last 30 Days"
      when "all" then "All Time"
      when "custom"
        if @time_window
          "#{@time_window.begin.strftime('%b %d, %Y')} – #{@time_window.end.strftime('%b %d, %Y')}"
        else
          "Custom Range"
        end
      else
        "Last 7 Days"
      end
    end

    private

    def tasks_unfiltered
      admin_or_auditor? ? Task.all : user.tasks
    end

    def executions_unfiltered
      admin_or_auditor? ? Execution.all : Execution.where(task_id: tasks_unfiltered.select(:id))
    end

    def calculate_time_window
      now = Time.current
      case @range
      when "24h"
        24.hours.ago..now
      when "7d"
        7.days.ago..now
      when "30d"
        30.days.ago..now
      when "all"
        nil
      when "custom"
        parse_custom_range(now)
      else
        7.days.ago..now
      end
    end

    def parse_custom_range(now)
      start_time = begin
        Time.zone.parse(@start_date.to_s)&.beginning_of_day
      rescue StandardError
        nil
      end

      end_time = begin
        Time.zone.parse(@end_date.to_s)&.end_of_day
      rescue StandardError
        nil
      end

      if start_time && end_time
        start_time..end_time
      elsif start_time
        start_time..now
      elsif end_time
        1.year.ago..end_time
      else
        7.days.ago..now
      end
    end
  end
end
