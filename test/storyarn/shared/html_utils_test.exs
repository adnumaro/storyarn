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

    test "strips inline formatting tags" do
      assert HtmlUtils.strip_html("<p>Hello <strong>world</strong></p>") == "Hello world"
      assert HtmlUtils.strip_html("<em>italic</em>") == "italic"
      assert HtmlUtils.strip_html("<b>bold</b> and <i>italic</i>") == "bold and italic"
    end

    test "strips nested tags" do
      assert HtmlUtils.strip_html("<p><strong><em>nested</em></strong></p>") == "nested"
    end

    test "converts <br> to newline" do
      assert HtmlUtils.strip_html("line1<br>line2") == "line1\nline2"
    end

    test "converts <br/> to newline" do
      assert HtmlUtils.strip_html("line1<br/>line2") == "line1\nline2"
    end

    test "converts <br /> to newline" do
      assert HtmlUtils.strip_html("line1<br />line2") == "line1\nline2"
    end

    test "converts </p><p> boundaries to newline" do
      assert HtmlUtils.strip_html("<p>paragraph one</p><p>paragraph two</p>") ==
               "paragraph one\nparagraph two"
    end

    test "converts </p> <p> boundaries with whitespace to newline" do
      assert HtmlUtils.strip_html("<p>one</p>  <p>two</p>") == "one\ntwo"
    end

    test "handles </p><p> with attributes" do
      assert HtmlUtils.strip_html("<p>one</p><p class=\"indent\">two</p>") == "one\ntwo"
    end

    test "decodes &amp; entity" do
      assert HtmlUtils.strip_html("Tom &amp; Jerry") == "Tom & Jerry"
    end

    test "decodes &lt; entity" do
      assert HtmlUtils.strip_html("a &lt; b") == "a < b"
    end

    test "decodes &gt; entity" do
      assert HtmlUtils.strip_html("a &gt; b") == "a > b"
    end

    test "decodes &quot; entity" do
      assert HtmlUtils.strip_html("say &quot;hello&quot;") == "say \"hello\""
    end

    test "decodes &#39; entity" do
      assert HtmlUtils.strip_html("it&#39;s fine") == "it's fine"
    end

    test "decodes &nbsp; entity" do
      assert HtmlUtils.strip_html("hello&nbsp;world") == "hello world"
    end

    test "decodes multiple entity types in one string" do
      assert HtmlUtils.strip_html("&lt;div&gt; &amp; &quot;hi&quot;") ==
               "<div> & \"hi\""
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

  # ===========================================================================
  # strip_and_truncate/2
  # ===========================================================================

  describe "strip_and_truncate/2" do
    test "returns nil for nil input" do
      assert HtmlUtils.strip_and_truncate(nil, 40) == nil
    end

    test "returns nil for empty string input" do
      assert HtmlUtils.strip_and_truncate("", 40) == nil
    end

    test "returns nil for whitespace-only input" do
      assert HtmlUtils.strip_and_truncate("   ", 40) == nil
    end

    test "returns nil for HTML-only content that becomes empty" do
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
      assert String.length(result) == 5
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

    test "handles HTML with entities (entities NOT decoded in strip_and_truncate)" do
      # Note: strip_and_truncate uses a simpler tag-stripping regex
      # and does NOT call decode_entities, so &amp; stays as-is
      result = HtmlUtils.strip_and_truncate("<p>A &amp; B</p>", 40)
      assert result == "A &amp; B"
    end
  end
end
