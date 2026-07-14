defmodule Storyarn.Shared.HtmlUtilsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.HtmlUtils

  # ===========================================================================
  # strip_html/1
  # ===========================================================================

  describe "strip_html/1" do
    test "returns empty string for nil" do
      assert HtmlUtils.strip_html(nil) == ""
    end

    test "returns empty string for empty string" do
      assert HtmlUtils.strip_html("") == ""
    end

    test "returns plain text unchanged" do
      assert HtmlUtils.strip_html("plain text") == "plain text"
    end

    test "strips basic HTML tags" do
      assert HtmlUtils.strip_html("<p>Hello world</p>") == "Hello world"
    end

    test "strips nested tags" do
      assert HtmlUtils.strip_html("<p><strong><em>nested</em></strong></p>") == "nested"
    end

    test "converts all <br> variants to newline" do
      assert HtmlUtils.strip_html("line1<br>line2") == "line1\nline2"
      assert HtmlUtils.strip_html("line1<br/>line2") == "line1\nline2"
      assert HtmlUtils.strip_html("line1<br />line2") == "line1\nline2"
    end

    test "converts </p><p> boundaries to newline" do
      assert HtmlUtils.strip_html("<p>paragraph one</p><p>paragraph two</p>") ==
               "paragraph one\nparagraph two"

      assert HtmlUtils.strip_html("<p>one</p>  <p>two</p>") == "one\ntwo"
    end

    test "handles </p><p> with attributes" do
      assert HtmlUtils.strip_html("<p>one</p><p class=\"indent\">two</p>") == "one\ntwo"
    end

    test "decodes HTML entities" do
      assert HtmlUtils.strip_html("Tom &amp; Jerry") == "Tom & Jerry"
      assert HtmlUtils.strip_html("a &lt; b") == "a < b"
      assert HtmlUtils.strip_html("a &gt; b") == "a > b"
      assert HtmlUtils.strip_html("say &quot;hello&quot;") == "say \"hello\""
      assert HtmlUtils.strip_html("it&#39;s fine") == "it's fine"
      assert HtmlUtils.strip_html("hello&nbsp;world") == "hello world"
    end

    test "trims surrounding whitespace" do
      assert HtmlUtils.strip_html("  <p> hello </p>  ") == "hello"
    end

    test "handles complex Tiptap-style HTML" do
      html = "<p>Hello <strong>bold</strong> and <em>italic</em></p><p>New paragraph</p>"
      assert HtmlUtils.strip_html(html) == "Hello bold and italic\nNew paragraph"
    end

    test "handles tags with attributes" do
      assert HtmlUtils.strip_html("<a href=\"http://example.com\">link</a>") == "link"
      assert HtmlUtils.strip_html("<span class=\"red\">colored</span>") == "colored"
    end

    test "handles multiple <br> tags" do
      assert HtmlUtils.strip_html("a<br>b<br>c") == "a\nb\nc"
    end
  end

  describe "add_heading_ids/1" do
    test "normalizes inline HTML consistently" do
      html = "<h2>Hello <code>World &amp; friends</code></h2>"

      assert HtmlUtils.add_heading_ids(html) ==
               ~s(<h2 id="hello-world-friends">Hello <code>World &amp; friends</code></h2>)
    end

    test "preserves Unicode letters and numbers" do
      assert HtmlUtils.add_heading_ids("<h2>Cómo diseñar 日本語 2</h2>") ==
               ~s(<h2 id="cómo-diseñar-日本語-2">Cómo diseñar 日本語 2</h2>)
    end

    test "suffixes duplicate and empty heading IDs deterministically" do
      html = "<h2>Setup</h2><h3>Setup</h3><h2>🎮</h2><h2>🎮</h2>"

      assert HtmlUtils.add_heading_ids(html) ==
               ~s(<h2 id="setup">Setup</h2><h3 id="setup-2">Setup</h3><h2 id="section">🎮</h2><h2 id="section-2">🎮</h2>)
    end

    test "preserves opening-tag attributes and explicit IDs" do
      html =
        ~s(<h2 class="title">Generated</h2><h3 class="title" id='custom'>Custom</h3>)

      normalized = HtmlUtils.add_heading_ids(html)

      assert normalized ==
               ~s(<h2 id="generated" class="title">Generated</h2><h3 class="title" id='custom'>Custom</h3>)

      assert HtmlUtils.heading_outline(normalized) == [
               %{level: 2, id: "generated", text: "Generated"},
               %{level: 3, id: "custom", text: "Custom"}
             ]
    end

    test "replaces an empty explicit ID without duplicating the attribute" do
      assert HtmlUtils.add_heading_ids(~s(<h2 class="title" id="">Fallback</h2>)) ==
               ~s(<h2 class="title" id="fallback">Fallback</h2>)
    end

    test "does not treat id-like text inside another attribute value as an ID" do
      html =
        ~s(<h2 data-note="id=fake">Real heading</h2><h3 title="contains id='also-fake'">Next</h3>)

      normalized = HtmlUtils.add_heading_ids(html)

      assert normalized ==
               ~s(<h2 id="real-heading" data-note="id=fake">Real heading</h2><h3 id="next" title="contains id='also-fake'">Next</h3>)

      assert HtmlUtils.heading_outline(normalized) == [
               %{level: 2, id: "real-heading", text: "Real heading"},
               %{level: 3, id: "next", text: "Next"}
             ]
    end

    test "reserves explicit IDs before assigning generated IDs" do
      html =
        ~s(<h2>Setup</h2><h2 id="setup">Explicit setup</h2><h3>Setup</h3><h3 id="setup-2">Explicit suffix</h3>)

      normalized = HtmlUtils.add_heading_ids(html)

      assert normalized ==
               ~s(<h2 id="setup-3">Setup</h2><h2 id="setup">Explicit setup</h2><h3 id="setup-4">Setup</h3><h3 id="setup-2">Explicit suffix</h3>)

      assert normalized
             |> HtmlUtils.heading_outline()
             |> Enum.map(& &1.id) == ["setup-3", "setup", "setup-4", "setup-2"]
    end
  end

  # ===========================================================================
  # strip_and_truncate/2
  # ===========================================================================

  describe "strip_and_truncate/2" do
    test "returns nil for empty or blank inputs" do
      assert HtmlUtils.strip_and_truncate(nil, 40) == nil
      assert HtmlUtils.strip_and_truncate("", 40) == nil
      assert HtmlUtils.strip_and_truncate("   ", 40) == nil
      assert HtmlUtils.strip_and_truncate("<p></p>", 40) == nil
    end

    test "strips HTML and returns plain text" do
      assert HtmlUtils.strip_and_truncate("<p>Hello world</p>", 40) == "Hello world"
    end

    test "truncates to max_length" do
      assert HtmlUtils.strip_and_truncate("<p>Hello world</p>", 5) == "Hello"
    end

    test "does not truncate when text is shorter than max_length" do
      assert HtmlUtils.strip_and_truncate("<p>Hi</p>", 40) == "Hi"
    end

    test "truncates exactly at max_length" do
      result = HtmlUtils.strip_and_truncate("abcdefghij", 5)
      assert result == "abcde"
    end

    test "uses default max_length of 40" do
      long_text = String.duplicate("a", 50)
      result = HtmlUtils.strip_and_truncate(long_text)
      assert String.length(result) == 40
    end

    test "strips tags before truncating" do
      # "Hello" is 5 chars, without tags
      assert HtmlUtils.strip_and_truncate("<strong>Hello</strong> world", 5) == "Hello"
    end

    test "trims whitespace before truncating" do
      assert HtmlUtils.strip_and_truncate("  Hello  ", 5) == "Hello"
    end
  end
end
