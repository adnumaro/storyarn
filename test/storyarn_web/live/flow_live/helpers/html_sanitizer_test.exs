defmodule StoryarnWeb.FlowLive.Helpers.HtmlSanitizerTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.Helpers.HtmlSanitizer

  # ── Allowed tags pass through ──────────────────────────────────────

  describe "allowed tags" do
    test "preserves inline formatting tags" do
      html =
        "<p><strong>bold</strong> <em>italic</em> <b>b</b> <i>i</i> <u>u</u> <s>strike</s></p>"

      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<strong>bold</strong>"
      assert result =~ "<em>italic</em>"
      assert result =~ "<b>b</b>"
      assert result =~ "<i>i</i>"
      assert result =~ "<u>u</u>"
      assert result =~ "<s>strike</s>"
    end

    test "preserves block-level tags" do
      html =
        "<div><p>paragraph</p><blockquote>quote</blockquote><pre><code>code</code></pre></div>"

      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<div>"
      assert result =~ "<p>paragraph</p>"
      assert result =~ "<blockquote>quote</blockquote>"
      assert result =~ "<pre><code>code</code></pre>"
    end

    test "preserves list tags" do
      html = "<ul><li>one</li><li>two</li></ul><ol><li>three</li></ol>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<ul><li>one</li><li>two</li></ul>"
      assert result =~ "<ol><li>three</li></ol>"
    end

    test "preserves heading tags h1 through h6" do
      for level <- 1..6 do
        tag = "h#{level}"
        html = "<#{tag}>heading</#{tag}>"
        result = HtmlSanitizer.sanitize_html(html)
        assert result =~ "<#{tag}>heading</#{tag}>"
      end
    end

    test "preserves anchor tags with safe href" do
      html = ~s[<a href="https://example.com">link</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[<a href="https://example.com">link</a>]
    end

    test "preserves br, span, sub, sup, del tags" do
      html = "<span>text</span><br><sub>sub</sub><sup>sup</sup><del>del</del>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<span>text</span>"
      assert result =~ "<br"
      assert result =~ "<sub>sub</sub>"
      assert result =~ "<sup>sup</sup>"
      assert result =~ "<del>del</del>"
    end
  end

  # ── Disallowed tags stripped ───────────────────────────────────────

  describe "disallowed tags" do
    test "strips script tags but preserves inner text as escaped content" do
      html = "<p>safe</p><script>alert('xss')</script>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>safe</p>"
      refute result =~ "<script>"
      # The text content of the script tag is preserved (escaped) since the
      # sanitizer strips tags but keeps text nodes. The script cannot execute.
      refute result =~ "<script"
    end

    test "strips iframe tags" do
      html = ~s[<p>text</p><iframe src="https://evil.com"></iframe>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>text</p>"
      refute result =~ "<iframe"
    end

    test "strips object, embed, and applet tags" do
      html = ~s[<object data="x"></object><embed src="y"><applet code="z"></applet>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "<object"
      refute result =~ "<embed"
      refute result =~ "<applet"
    end

    test "strips form and style tags" do
      html = ~s[<form action="/steal"><input></form><style>body{display:none}</style><p>safe</p>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "<form"
      refute result =~ "<input"
      refute result =~ "<style"
      assert result =~ "<p>safe</p>"
    end

    test "preserves text content of stripped tags" do
      html = "<div><span>keep</span></div>"
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ "keep"
    end

    test "unwraps children of disallowed tags into parent" do
      html = "<div><marquee><p>preserved</p></marquee></div>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>preserved</p>"
      refute result =~ "<marquee"
    end
  end

  # ── Event handler attributes removed ──────────────────────────────

  describe "event handler attributes" do
    test "removes onclick attribute" do
      html = ~s[<p onclick="alert('xss')">text</p>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>text</p>"
      refute result =~ "onclick"
    end

    test "removes onload attribute" do
      html = ~s[<div onload="fetch('/steal')">content</div>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<div>content</div>"
      refute result =~ "onload"
    end

    test "removes onerror and onmouseover attributes" do
      html = ~s[<span onerror="evil()" onmouseover="steal()">text</span>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<span>text</span>"
      refute result =~ "onerror"
      refute result =~ "onmouseover"
    end

    test "removes event handlers regardless of case" do
      html = ~s[<p OnClick="x" ONLOAD="y">text</p>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>text</p>"
      refute result =~ "OnClick"
      refute result =~ "ONLOAD"
    end
  end

  # ── Dangerous attributes removed ──────────────────────────────────

  describe "dangerous attributes" do
    test "removes style attribute" do
      html = ~s[<p style="color: red">text</p>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>text</p>"
      refute result =~ "style"
    end

    test "removes srcdoc attribute" do
      html = ~s[<div srcdoc="<script>alert(1)</script>">text</div>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "srcdoc"
    end

    test "removes formaction attribute" do
      html = ~s[<div formaction="https://evil.com">text</div>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "formaction"
    end
  end

  # ── javascript: URIs blocked ──────────────────────────────────────

  describe "javascript: URI blocking" do
    test "removes href with javascript: scheme" do
      html = ~s[<a href="javascript:alert('xss')">click</a>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<a>click</a>"
      refute result =~ "javascript:"
    end

    test "removes href with mixed-case javascript: scheme" do
      html = ~s[<a href="JavaScript:void(0)">click</a>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "javascript:"
      refute result =~ "JavaScript:"
    end

    test "removes href with whitespace-padded javascript: scheme" do
      html = ~s[<a href="  javascript:alert(1)">click</a>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "javascript:"
    end
  end

  # ── data: URIs blocked ────────────────────────────────────────────

  describe "data: URI blocking" do
    test "removes href with data: scheme" do
      html = ~s[<a href="data:text/html,<script>alert(1)</script>">click</a>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "data:"
    end

    test "removes src with data: scheme containing base64" do
      # Note: img is not in the allowed tags list, so the whole tag is stripped.
      # Test with an allowed tag that could theoretically have a src attribute.
      html = ~s[<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">x</a>]
      result = HtmlSanitizer.sanitize_html(html)

      refute result =~ "data:"
    end
  end

  # ── Safe URIs preserved ───────────────────────────────────────────

  describe "safe URIs" do
    test "preserves https href" do
      html = ~s[<a href="https://example.com">link</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[href="https://example.com"]
    end

    test "preserves http href" do
      html = ~s[<a href="http://example.com">link</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[href="http://example.com"]
    end

    test "preserves mailto href" do
      html = ~s[<a href="mailto:user@example.com">email</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[href="mailto:user@example.com"]
    end

    test "preserves tel href" do
      html = ~s[<a href="tel:+1234567890">call</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[href="tel:+1234567890"]
    end

    test "preserves fragment href" do
      html = ~s[<a href="#section">jump</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[href="#section"]
    end

    test "preserves relative path href" do
      html = ~s[<a href="/about/team">team</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[href="/about/team"]
    end

    test "preserves empty href" do
      html = ~s[<a href="">link</a>]
      result = HtmlSanitizer.sanitize_html(html)
      assert result =~ ~s[href=""]
    end
  end

  # ── HTML comments stripped ────────────────────────────────────────

  describe "HTML comments" do
    test "strips HTML comments" do
      html = "<p>before</p><!-- secret comment --><p>after</p>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>before</p>"
      assert result =~ "<p>after</p>"
      refute result =~ "<!--"
      refute result =~ "secret comment"
    end

    test "strips conditional comments" do
      html = "<p>text</p><!--[if IE]><script>alert(1)</script><![endif]-->"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>text</p>"
      refute result =~ "<!--"
      refute result =~ "script"
    end
  end

  # ── Empty / nil / non-string input ────────────────────────────────

  describe "edge case inputs" do
    test "empty string returns empty string" do
      assert HtmlSanitizer.sanitize_html("") == ""
    end

    test "nil returns empty string" do
      assert HtmlSanitizer.sanitize_html(nil) == ""
    end

    test "integer returns empty string" do
      assert HtmlSanitizer.sanitize_html(42) == ""
    end

    test "atom returns empty string" do
      assert HtmlSanitizer.sanitize_html(:not_html) == ""
    end

    test "list returns empty string" do
      assert HtmlSanitizer.sanitize_html(["<p>text</p>"]) == ""
    end

    test "plain text without tags passes through" do
      assert HtmlSanitizer.sanitize_html("just plain text") =~ "just plain text"
    end
  end

  # ── Nested unsafe content stripped recursively ────────────────────

  describe "nested unsafe content" do
    test "strips deeply nested script tags" do
      html = "<div><p><span><script>alert(1)</script>safe</span></p></div>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "safe"
      refute result =~ "<script>"
      # Text content of script is preserved as plain text (not executable)
    end

    test "strips nested disallowed tags but preserves allowed children" do
      html = "<div><form><p><strong>important</strong></p></form></div>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p><strong>important</strong></p>"
      refute result =~ "<form"
    end

    test "handles multiple levels of disallowed nesting" do
      html = "<div><iframe><object><embed><p>deep text</p></embed></object></iframe></div>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p>deep text</p>"
      refute result =~ "<iframe"
      refute result =~ "<object"
      refute result =~ "<embed"
    end

    test "strips event handlers on nested allowed tags" do
      html = ~s[<div><p onclick="x"><strong onmouseover="y">text</strong></p></div>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "<p><strong>text</strong></p>"
      refute result =~ "onclick"
      refute result =~ "onmouseover"
    end
  end

  # ── Processing instructions trigger catch-all strip_unsafe_node ──

  describe "processing instructions (XML PI)" do
    test "XML processing instruction is stripped, content preserved" do
      # The <?xml ...?> PI produces {:pi, "xml", [{"version", "1.0"}]} in Floki's AST.
      # The 2-tuple attributes inside the PI hit the catch-all strip_unsafe_node(_),
      # covering the defensive fallback on line 35.
      result = HtmlSanitizer.sanitize_html("<?xml version=\"1.0\"?><p>hello</p>")
      assert result =~ "<p>hello</p>"
      refute result =~ "<?xml"
    end
  end

  # ── Malformed HTML handling ───────────────────────────────────────

  describe "malformed HTML" do
    test "handles unclosed tags" do
      html = "<p>unclosed paragraph<p>another"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "unclosed paragraph"
      assert result =~ "another"
    end

    test "handles mismatched closing tags" do
      html = "<p>text</div></p>"
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ "text"
    end

    test "preserves safe attributes and strips unsafe ones on same tag" do
      html = ~s[<a href="https://ok.com" onclick="evil()" class="link">text</a>]
      result = HtmlSanitizer.sanitize_html(html)

      assert result =~ ~s[href="https://ok.com"]
      assert result =~ ~s[class="link"]
      refute result =~ "onclick"
    end
  end
end
