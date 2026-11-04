module Governance
  class ApprovalAnalytics
    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    def calculate
      approvals = scope.approvals
      now = Time.current

      pending_count = approvals.where(status: "pending").where("expires_at IS NULL OR expires_at > ?", now).count
      approved_count = approvals.where(status: %w[approved executed]).count
      rejected_count = approvals.where(status: "rejected").count
      expired_count = approvals.where("status = 'expired' OR (status = 'pending' AND expires_at <= ?)", now).count

      total_decided = approved_count + rejected_count + expired_count
      total_all = pending_count + total_decided

      distribution = if total_decided > 0
        {
          approved_pct: (approved_count.to_f / total_decided * 100).round(1),
          rejected_pct: (rejected_count.to_f / total_decided * 100).round(1),
          expired_pct: (expired_count.to_f / total_decided * 100).round(1)
        }
      else
        { approved_pct: 0.0, rejected_pct: 0.0, expired_pct: 0.0 }
      end

      # Average approval waiting time (in seconds) for reviewed/decided approvals
      avg_waiting_time_seconds = calculate_avg_waiting_time(approvals)

      # Top approved action types
      top_approved_action_types = approvals.where(status: %w[approved executed])
                                           .where.not(tool_name: nil)
                                           .group(:tool_name)
                                           .order("count_all desc")
                                           .limit(5)
                                           .count

      # Top rejected action types
      top_rejected_action_types = approvals.where(status: "rejected")
                                           .where.not(tool_name: nil)
                                           .group(:tool_name)
                                           .order("count_all desc")
                                           .limit(5)
                                           .count

      # Stale / near-expiration requests
      stale_approvals = approvals.where(status: "pending")
                                 .where("expires_at IS NOT NULL AND expires_at > ? AND expires_at <= ?", now, now + 24.hours)
                                 .order(expires_at: :asc)
                                 .limit(5)

      # Activity over time
      activity_over_time = build_activity_timeline(approvals)

      {
        pending_count: pending_count,
        approved_count: approved_count,
        rejected_count: rejected_count,
        expired_count: expired_count,
        total_decided: total_decided,
        total_all: total_all,
        distribution: distribution,
        avg_waiting_time_seconds: avg_waiting_time_seconds,
        formatted_avg_waiting_time: format_duration(avg_waiting_time_seconds),
        top_approved_action_types: top_approved_action_types,
        top_rejected_action_types: top_rejected_action_types,
        stale_approvals: stale_approvals,
        activity_over_time: activity_over_time
      }
    end

    private

    def calculate_avg_waiting_time(approvals)
      # Only consider decided requests with both request and review timestamps
      decided = approvals.where.not(reviewed_at: nil)
      return nil if decided.empty?

      durations = decided.limit(500).map do |appr|
        start = appr.requested_at || appr.created_at
        appr.reviewed_at && start ? (appr.reviewed_at - start).to_f : nil
      end.compact

      return nil if durations.empty?

      (durations.sum / durations.size).round(1)
    end

    def format_duration(seconds)
      return "Unavailable" if seconds.nil? || seconds < 0

      if seconds < 60
        "#{seconds.round(1)}s"
      elsif seconds < 3600
        mins = (seconds / 60).to_i
        secs = (seconds % 60).round(0)
        "#{mins}m #{secs}s"
      else
        hours = (seconds / 3600).round(1)
        "#{hours}h"
      end
    end

    def build_activity_timeline(approvals)
      timeline = {}
      approvals.order(created_at: :asc).limit(500).each do |appr|
        date_key = appr.created_at.strftime("%Y-%m-%d")
        timeline[date_key] ||= { "requested" => 0, "approved" => 0, "rejected" => 0, "expired" => 0 }
        timeline[date_key]["requested"] += 1
        case appr.status
        when "approved", "executed"
          timeline[date_key]["approved"] += 1
        when "rejected"
          timeline[date_key]["rejected"] += 1
        when "expired"
          timeline[date_key]["expired"] += 1
        end
      end
      timeline
    end
  end
end
