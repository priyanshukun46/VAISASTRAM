require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "format_ai_response formats paragraphs and stanzas with bold and line breaks" do
    sample = <<~SONG
      Sure thing! Here's a little song:

      **Verse 1**
      Line one of stanza
      Line two of stanza

      **Chorus**
      Sing it loud
    SONG

    result = format_ai_response(sample)
    assert_includes result, '<strong class="font-bold text-slate-900">Verse 1</strong>'
    assert_includes result, "Line one of stanza<br/>Line two of stanza"
    assert_includes result, '<strong class="font-bold text-slate-900">Chorus</strong>'
  end

  test "format_ai_response safely escapes HTML to prevent XSS" do
    malicious = "<script>alert('xss')</script>**bold**"
    result = format_ai_response(malicious)
    assert_not_includes result, "<script>"
    assert_includes result, "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
    assert_includes result, '<strong class="font-bold text-slate-900">bold</strong>'
  end

  test "format_ai_response formats code blocks and inline code" do
    code_text = "Check this:\n```ruby\ndef add(a, b); a + b; end\n```\nUse `add(1, 2)`."
    result = format_ai_response(code_text)
    assert_includes result, "<pre class=\"bg-slate-900 text-slate-100"
    assert_includes result, "def add(a, b); a + b; end"
    assert_includes result, "<code class=\"bg-slate-100 text-[#7c5cfc]"
    assert_includes result, "add(1, 2)"
  end

  test "format_ai_response handles blank input" do
    assert_equal "", format_ai_response(nil)
    assert_equal "", format_ai_response("")
  end
end
