module ApplicationHelper
  def nav_link_to(name, path, options = {})
    is_active = current_page?(path)
    base_classes = "inline-flex items-center px-3 py-2 text-sm font-medium rounded-md transition-colors"
    active_classes = is_active ? "bg-slate-800 text-white" : "text-slate-300 hover:bg-slate-800/60 hover:text-white"
    classes = "#{base_classes} #{active_classes} #{options[:class]}".strip

    link_to name, path, options.merge(class: classes)
  end

  def status_badge(status)
    case status.to_s.downcase
    when "operational", "completed", "approved", "active", "allow"
      content_tag(:span, status.to_s.capitalize, class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-emerald-950 text-emerald-400 border border-emerald-800")
    when "pending", "paused", "waiting_approval", "standby"
      content_tag(:span, status.to_s.humanize, class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-amber-950 text-amber-400 border border-amber-800")
    when "blocked", "rejected", "failed", "error", "deny"
      content_tag(:span, status.to_s.capitalize, class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-rose-950 text-rose-400 border border-rose-800")
    else
      content_tag(:span, status.to_s.humanize, class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-slate-800 text-slate-300 border border-slate-700")
    end
  end

  def risk_badge(risk_level)
    case risk_level.to_s.downcase
    when "low"
      content_tag(:span, "LOW RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-blue-950 text-blue-400 border border-blue-800")
    when "medium"
      content_tag(:span, "MEDIUM RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-amber-950 text-amber-400 border border-amber-800")
    when "high"
      content_tag(:span, "HIGH RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-orange-950 text-orange-400 border border-orange-800")
    when "critical"
      content_tag(:span, "CRITICAL RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-bold bg-rose-950 text-rose-300 border border-rose-800")
    else
      content_tag(:span, risk_level.to_s.upcase, class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-slate-800 text-slate-300 border border-slate-700")
    end
  end
end
