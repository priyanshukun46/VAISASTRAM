module ApplicationHelper
  # Official VAISASTRAM Mascot Emblem (Robot Head + Scales of Justice)
  def vaisastram_mascot_svg(classes: "w-8 h-8", variant: :dark)
    primary_color = variant == :light ? "#ffffff" : "#1E1250"
    visor_color = variant == :light ? "#0d0726" : "#E8E8E3"

    raw <<~SVG
      <svg class="#{classes}" viewBox="0 0 58 74" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="VAISASTRAM Mascot">
        <!-- scales of justice -->
        <circle cx="29" cy="3.5" r="2.6" fill="#{primary_color}"/>
        <rect x="27.8" y="5" width="2.4" height="13" fill="#{primary_color}"/>
        <rect x="5" y="6.2" width="48" height="2.4" rx="1.2" fill="#{primary_color}"/>
        <g stroke="#{primary_color}" stroke-width="1.2" fill="none">
          <path d="M7 8 L1.5 19 M7 8 L12.5 19"/>
          <path d="M51 8 L45.5 19 M51 8 L56.5 19"/>
        </g>
        <path d="M0 19 H14 Q13 25 7 25 Q1 25 0 19Z" fill="#{primary_color}"/>
        <path d="M44 19 H58 Q57 25 51 25 Q45 25 44 19Z" fill="#{primary_color}"/>
        <!-- head -->
        <path d="M7 49 C7 33 17 25 29 25 C41 25 51 33 51 49 L51 66 Q51 72 45 72 L13 72 Q7 72 7 66Z" fill="#{primary_color}"/>
        <!-- visor -->
        <rect x="13" y="38" width="32" height="20" rx="8" fill="#{visor_color}"/>
        <!-- eyes -->
        <circle cx="23" cy="48" r="4" fill="#{primary_color}"/>
        <circle cx="35" cy="48" r="4" fill="#{primary_color}"/>
        <!-- chin vent -->
        <rect x="22" y="64" width="14" height="3" rx="1.5" fill="#{visor_color}"/>
      </svg>
    SVG
  end

  # Official VAISASTRAM Full Vector Logo (Mascot + Outlined Wordmark)
  def vaisastram_logo_svg(classes: "h-8 w-auto", variant: :dark)
    primary_color = variant == :light ? "#ffffff" : "#1E1250"
    visor_color = variant == :light ? "#0d0726" : "#E8E8E3"

    raw <<~SVG
      <svg class="#{classes}" viewBox="0 0 380 84" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="VAISASTRAM logo">
        <!-- mascot icon -->
        <g transform="translate(4, 6)">
          <!-- scales of justice -->
          <circle cx="29" cy="3.5" r="2.6" fill="#{primary_color}"/>
          <rect x="27.8" y="5" width="2.4" height="13" fill="#{primary_color}"/>
          <rect x="5" y="6.2" width="48" height="2.4" rx="1.2" fill="#{primary_color}"/>
          <g stroke="#{primary_color}" stroke-width="1.2" fill="none">
            <path d="M7 8 L1.5 19 M7 8 L12.5 19"/>
            <path d="M51 8 L45.5 19 M51 8 L56.5 19"/>
          </g>
          <path d="M0 19 H14 Q13 25 7 25 Q1 25 0 19Z" fill="#{primary_color}"/>
          <path d="M44 19 H58 Q57 25 51 25 Q45 25 44 19Z" fill="#{primary_color}"/>
          <!-- head -->
          <path d="M7 49 C7 33 17 25 29 25 C41 25 51 33 51 49 L51 66 Q51 72 45 72 L13 72 Q7 72 7 66Z" fill="#{primary_color}"/>
          <!-- visor -->
          <rect x="13" y="38" width="32" height="20" rx="8" fill="#{visor_color}"/>
          <!-- eyes -->
          <circle cx="23" cy="48" r="4" fill="#{primary_color}"/>
          <circle cx="35" cy="48" r="4" fill="#{primary_color}"/>
          <!-- chin vent -->
          <rect x="22" y="64" width="14" height="3" rx="1.5" fill="#{visor_color}"/>
        </g>
        <!-- wordmark (outlined, no font needed) -->
        <g transform="translate(78, 59)" fill="#{primary_color}">
          <path d="M0.1669921875 -27.7021484375H6.6240234375L13.248046875 -7.2548828125L19.8349609375 -27.7021484375H26.310546875L17.0703125 0.0H9.4072265625Z M47.7353515625 -5.046875H37.6787109375L36.0830078125 0.0H29.6259765625L38.8662109375 -27.7021484375H46.529296875L55.76953125 0.0H49.2939453125ZM39.2744140625 -10.1865234375H46.1025390625L42.70703125 -21.2080078125Z M62.0537109375 -27.7021484375H68.4921875V0.0H62.0537109375Z M95.1123046875 -26.830078125V-20.966796875Q93.0712890625 -21.9873046875 91.11376953125 -22.5068359375Q89.15625 -23.0263671875 87.412109375 -23.0263671875Q85.111328125 -23.0263671875 84.00732421875 -22.3212890625Q82.9033203125 -21.6162109375 82.9033203125 -20.1318359375Q82.9033203125 -19.0185546875 83.6455078125 -18.39697265625Q84.3876953125 -17.775390625 86.3544921875 -17.330078125L89.08203125 -16.7177734375Q93.2568359375 -15.7900390625 95.0009765625 -13.8974609375Q96.7451171875 -12.0048828125 96.7451171875 -8.5166015625Q96.7451171875 -3.93359375 94.30517578125 -1.69775390625Q91.865234375 0.5380859375 86.8369140625 0.5380859375Q84.4619140625 0.5380859375 82.07763671875 0.037109375Q79.693359375 -0.4638671875 77.2998046875 -1.447265625V-7.4775390625Q79.693359375 -6.0673828125 81.919921875 -5.35302734375Q84.146484375 -4.638671875 86.224609375 -4.638671875Q88.3212890625 -4.638671875 89.44384765625 -5.41796875Q90.56640625 -6.197265625 90.56640625 -7.64453125Q90.56640625 -8.943359375 89.8056640625 -9.6484375Q89.044921875 -10.353515625 86.7626953125 -10.91015625L84.2763671875 -11.5224609375Q80.546875 -12.4130859375 78.81201171875 -14.361328125Q77.0771484375 -16.3095703125 77.0771484375 -19.6123046875Q77.0771484375 -23.75 79.4892578125 -25.9765625Q81.9013671875 -28.203125 86.3916015625 -28.203125Q88.451171875 -28.203125 90.6220703125 -27.85986328125Q92.79296875 -27.5166015625 95.1123046875 -26.830078125Z M120.5263671875 -5.046875H110.4697265625L108.8740234375 0.0H102.4169921875L111.6572265625 -27.7021484375H119.3203125L128.560546875 0.0H122.0849609375ZM112.0654296875 -10.1865234375H118.8935546875L115.498046875 -21.2080078125Z M152.193359375 -26.830078125V-20.966796875Q150.15234375 -21.9873046875 148.19482421875 -22.5068359375Q146.2373046875 -23.0263671875 144.4931640625 -23.0263671875Q142.1923828125 -23.0263671875 141.08837890625 -22.3212890625Q139.984375 -21.6162109375 139.984375 -20.1318359375Q139.984375 -19.0185546875 140.7265625 -18.39697265625Q141.46875 -17.775390625 143.435546875 -17.330078125L146.1630859375 -16.7177734375Q150.337890625 -15.7900390625 152.08203125 -13.8974609375Q153.826171875 -12.0048828125 153.826171875 -8.5166015625Q153.826171875 -3.93359375 151.38623046875 -1.69775390625Q148.9462890625 0.5380859375 143.91796875 0.5380859375Q141.54296875 0.5380859375 139.15869140625 0.037109375Q136.7744140625 -0.4638671875 134.380859375 -1.447265625V-7.4775390625Q136.7744140625 -6.0673828125 139.0009765625 -5.35302734375Q141.2275390625 -4.638671875 143.3056640625 -4.638671875Q145.40234375 -4.638671875 146.52490234375 -5.41796875Q147.6474609375 -6.197265625 147.6474609375 -7.64453125Q147.6474609375 -8.943359375 146.88671875 -9.6484375Q146.1259765625 -10.353515625 143.84375 -10.91015625L141.357421875 -11.5224609375Q137.6279296875 -12.4130859375 135.89306640625 -14.361328125Q134.158203125 -16.3095703125 134.158203125 -19.6123046875Q134.158203125 -23.75 136.5703125 -25.9765625Q138.982421875 -28.203125 143.47265625 -28.203125Q145.5322265625 -28.203125 147.703125 -27.85986328125Q149.8740234375 -27.5166015625 152.193359375 -26.830078125Z M159.498046875 -27.7021484375H182.46875V-22.302734375H174.2119140625V0.0H167.7734375V-22.302734375H159.498046875Z M197.9375 -15.4189453125Q199.94140625 -15.4189453125 200.82275390625 -16.25390625Q201.7041015625 -17.0888671875 201.7041015625 -19.0Q201.7041015625 -20.892578125 200.82275390625 -21.708984375Q199.94140625 -22.525390625 197.9375 -22.525390625H195.228515625V-15.4189453125ZM195.228515625 -10.4833984375V0.0H188.7900390625V-27.7021484375H198.60546875Q203.541015625 -27.7021484375 205.83251953125 -25.865234375Q208.1240234375 -24.0283203125 208.1240234375 -20.0576171875Q208.1240234375 -17.3115234375 206.9365234375 -15.548828125Q205.7490234375 -13.7861328125 203.3369140625 -12.951171875Q204.654296875 -12.6171875 205.70263671875 -11.43896484375Q206.7509765625 -10.2607421875 207.80859375 -7.8671875L211.296875 0.0H204.4501953125L201.42578125 -6.8837890625Q200.498046875 -8.9619140625 199.5517578125 -9.72265625Q198.60546875 -10.4833984375 197.046875 -10.4833984375Z M233.259765625 -5.046875H223.203125L221.607421875 0.0H215.150390625L224.390625 -27.7021484375H232.0537109375L241.2939453125 0.0H234.818359375ZM224.798828125 -10.1865234375H231.626953125L228.2314453125 -21.2080078125Z M247.578125 -27.7021484375H255.7607421875L261.4384765625 -12.876953125L267.1533203125 -27.7021484375H275.3173828125V0.0H269.2314453125V-20.26171875L263.498046875 -5.3251953125H259.416015625L253.6826171875 -20.26171875V0.0H247.578125Z"/>
        </g>
      </svg>
    SVG
  end

  def nav_link_to(name, path, options = {})
    is_active = current_page?(path)
    base_classes = "inline-flex items-center px-3.5 py-1.5 text-xs font-semibold uppercase tracking-wider rounded-md transition-all duration-150"
    active_classes = is_active ? "bg-[#0d0726] text-white shadow-sm" : "text-slate-700 hover:text-black hover:bg-black/5"
    classes = "#{base_classes} #{active_classes} #{options[:class]}".strip

    link_to name, path, options.merge(class: classes)
  end

  def status_badge(status)
    case status.to_s.downcase
    when "operational", "completed", "approved", "active", "allow"
      content_tag(:span, status.to_s.capitalize, class: "inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono font-semibold bg-[#ccff00]/20 text-emerald-950 border border-[#ccff00]")
    when "pending", "paused", "waiting_approval", "standby"
      content_tag(:span, status.to_s.humanize, class: "inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono font-semibold bg-amber-100 text-amber-900 border border-amber-300")
    when "blocked", "rejected", "failed", "error", "deny"
      content_tag(:span, status.to_s.capitalize, class: "inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono font-semibold bg-rose-100 text-rose-900 border border-rose-300")
    else
      content_tag(:span, status.to_s.humanize, class: "inline-flex items-center px-2 py-0.5 rounded text-[11px] font-mono font-medium bg-slate-100 text-slate-800 border border-slate-300")
    end
  end

  def risk_badge(risk_level)
    case risk_level.to_s.downcase
    when "low"
      content_tag(:span, "LOW RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-blue-100 text-blue-900 border border-blue-300")
    when "medium"
      content_tag(:span, "MEDIUM RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-amber-100 text-amber-900 border border-amber-300")
    when "high"
      content_tag(:span, "HIGH RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-orange-100 text-orange-900 border border-orange-300")
    when "critical"
      content_tag(:span, "CRITICAL RISK", class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-rose-100 text-rose-900 border border-rose-300")
    else
      content_tag(:span, risk_level.to_s.upcase, class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-mono font-medium bg-slate-100 text-slate-700 border border-slate-300")
    end
  end

  # Formats raw AI response text with Markdown formatting (paragraphs, line breaks, bold, italics, code blocks, lists)
  # while strictly sanitizing via ERB::Util.html_escape to guarantee zero XSS vulnerability.
  def format_ai_response(text)
    return "" if text.blank?

    escaped = ERB::Util.html_escape(text.to_s)

    # 1. Fenced code blocks ```lang\ncode\n```
    escaped = escaped.gsub(/```([a-zA-Z0-9_-]*)\n?(.*?)\n?```/m) do
      lang = Regexp.last_match(1).presence
      code = Regexp.last_match(2)
      header = lang ? "<div class=\"text-[10px] uppercase font-mono text-slate-400 bg-slate-800 px-3 py-1 rounded-t-lg border-b border-slate-700\">#{lang}</div>" : ""
      "#{header}<pre class=\"bg-slate-900 text-slate-100 p-3.5 #{lang ? 'rounded-b-lg' : 'rounded-lg'} font-mono text-xs overflow-x-auto my-2.5 leading-relaxed\"><code>#{code}</code></pre>"
    end

    # 2. Inline code `code`
    escaped = escaped.gsub(/`([^`\n]+)`/) do
      "<code class=\"bg-slate-100 text-[#7c5cfc] px-1.5 py-0.5 rounded font-mono text-xs border border-slate-200 font-semibold\">#{Regexp.last_match(1)}</code>"
    end

    # 3. Bold: **text** or __text__
    escaped = escaped.gsub(/(\*\*|__)(.*?)\1/) do
      "<strong class=\"font-bold text-slate-900\">#{Regexp.last_match(2)}</strong>"
    end

    # 4. Italics: *text* or _text_ (excluding inside words)
    escaped = escaped.gsub(/(?<!\w)([*_])([^*\n_]+)\1(?!\w)/) do
      "<em class=\"italic text-slate-700\">#{Regexp.last_match(2)}</em>"
    end

    # 5. Headers: ### H3, ## H2, # H1
    escaped = escaped.gsub(/^###\s+(.+)$/) { "<h3 class=\"font-black text-slate-900 text-sm mt-3 mb-1.5 uppercase font-sans tracking-tight\">#{Regexp.last_match(1)}</h3>" }
    escaped = escaped.gsub(/^##\s+(.+)$/) { "<h2 class=\"font-black text-slate-900 text-base mt-4 mb-2 uppercase font-sans tracking-tight\">#{Regexp.last_match(1)}</h2>" }
    escaped = escaped.gsub(/^#\s+(.+)$/) { "<h1 class=\"font-black text-slate-900 text-lg mt-4 mb-2 uppercase font-sans tracking-tight\">#{Regexp.last_match(1)}</h1>" }

    # 6. Blockquotes: > quote
    escaped = escaped.gsub(/^>\s+(.+)$/) do
      "<blockquote class=\"border-l-4 border-[#7c5cfc] pl-3 py-1 my-2 bg-slate-50 rounded-r text-slate-700 italic text-xs\">#{Regexp.last_match(1)}</blockquote>"
    end

    # 7. Split into paragraphs by double newlines, preserving single newlines as <br/> within stanzas/paragraphs
    paragraphs = escaped.split(/\n\s*\n/)
    formatted = paragraphs.map do |para|
      trimmed = para.strip
      next "" if trimmed.blank?
      if trimmed.start_with?("<pre", "<div class=\"text-[10px]", "<h1", "<h2", "<h3", "<blockquote")
        trimmed
      elsif trimmed.lines.all? { |line| line.strip.start_with?("- ", "* ") }
        items = trimmed.lines.map { |l| "<li class=\"list-disc ml-5 my-0.5 leading-relaxed text-sm text-slate-800\">#{l.strip.sub(/^[-*]\s+/, '')}</li>" }.join
        "<ul class=\"my-2 space-y-0.5\">#{items}</ul>"
      elsif trimmed.lines.all? { |line| line.strip.match?(/^\d+\.\s+/) }
        items = trimmed.lines.map { |l| "<li class=\"list-decimal ml-5 my-0.5 leading-relaxed text-sm text-slate-800\">#{l.strip.sub(/^\d+\.\s+/, '')}</li>" }.join
        "<ol class=\"my-2 space-y-0.5\">#{items}</ol>"
      else
        with_breaks = trimmed.gsub("\n", "<br/>")
        "<p class=\"text-sm text-slate-800 leading-relaxed font-normal my-2\">#{with_breaks}</p>"
      end
    end.reject(&:blank?).join("\n")

    raw(formatted)
  end
end
