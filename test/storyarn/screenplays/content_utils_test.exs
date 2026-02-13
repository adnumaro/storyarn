defmodule Storyarn.Screenplays.ContentUtilsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.ContentUtils

  describe "strip_html/1" do
    test "returns empty string for nil" do
      assert ContentUtils.strip_html(nil) == ""
    end

    test "returns empty string for empty input" do
      assert ContentUtils.strip_html("") == ""
    end

    test "passes through plain text" do
      assert ContentUtils.strip_html("Hello world") == "Hello world"
    end

    test "strips paragraph tags" do
      assert ContentUtils.strip_html("<p>Hello world</p>") == "Hello world"
    end

    test "strips bold and italic tags" do
      assert ContentUtils.strip_html("<p>Hello <strong>bold</strong> and <em>italic</em></p>") ==
               "Hello bold and italic"
    end

    test "converts br to newline" do
      assert ContentUtils.strip_html("Hello<br>world") == "Hello\nworld"
    end

    test "converts br with slash to newline" do
      assert ContentUtils.strip_html("Hello<br/>world") == "Hello\nworld"
    end

    test "converts consecutive paragraphs to newlines" do
      assert ContentUtils.strip_html("<p>Line one</p><p>Line two</p>") == "Line one\nLine two"
    end

    test "decodes HTML entities" do
      assert ContentUtils.strip_html("&amp; &lt; &gt; &quot; &#39;") == "& < > \" '"
    end

    test "decodes nbsp" do
      assert ContentUtils.strip_html("Hello&nbsp;world") == "Hello world"
    end

    test "strips mention spans" do
      html =
        ~s(<p>Talk to <span class="mention" data-id="42" data-label="Jaime">#Jaime</span></p>)

      assert ContentUtils.strip_html(html) == "Talk to #Jaime"
    end
  end

  describe "html?/1" do
    test "returns false for nil" do
      refute ContentUtils.html?(nil)
    end

    test "returns false for empty string" do
      refute ContentUtils.html?("")
    end

    test "returns false for plain text" do
      refute ContentUtils.html?("Hello world")
    end

    test "returns true for paragraph tag" do
      assert ContentUtils.html?("<p>Hello</p>")
    end

    test "returns true for span tag" do
      assert ContentUtils.html?("<span>Hello</span>")
    end

    test "returns false for angle brackets in text" do
      refute ContentUtils.html?("5 > 3")
    end
  end

  describe "sanitize_html/1 — XSS vectors" do
    test "strips script tags" do
      result = ContentUtils.sanitize_html("<script>alert('xss')</script><p>Safe</p>")
      refute result =~ "<script"
      assert result =~ "<p>Safe</p>"
    end

    test "strips img onerror" do
      result = ContentUtils.sanitize_html(~s[<img src=x onerror="alert(1)"><p>OK</p>])
      refute result =~ "onerror"
      refute result =~ "<img"
      assert result =~ "<p>OK</p>"
    end

    test "strips onclick attributes" do
      result = ContentUtils.sanitize_html(~s[<p onclick="alert(1)">Click me</p>])
      refute result =~ "onclick"
      assert result =~ "<p>Click me</p>"
    end

    test "strips javascript URLs in href" do
      # Build string to avoid Elixir keyword parser detection
      js_url = "java" <> "script" <> ":alert(1)"
      input = "<a href='#{js_url}'>Link</a>"
      result = ContentUtils.sanitize_html(input)
      refute result =~ js_url
    end

    test "strips iframe tags" do
      result = ContentUtils.sanitize_html(~s[<iframe src="evil.com"></iframe><p>Safe</p>])
      refute result =~ "<iframe"
      assert result =~ "<p>Safe</p>"
    end

    test "strips svg onload" do
      result = ContentUtils.sanitize_html(~s[<svg onload="alert(1)"><circle/></svg><p>OK</p>])
      refute result =~ "<svg"
      refute result =~ "onload"
      assert result =~ "<p>OK</p>"
    end

    test "strips style tags" do
      result = ContentUtils.sanitize_html(~s[<style>body{display:none}</style><p>Visible</p>])
      refute result =~ "<style"
      assert result =~ "<p>Visible</p>"
    end

    test "preserves allowed tags" do
      result = ContentUtils.sanitize_html("<p><strong>Bold</strong> and <em>italic</em></p>")
      assert result =~ "<strong>Bold</strong>"
      assert result =~ "<em>italic</em>"
    end
  end

  describe "plain_to_html/1" do
    test "wraps nil in empty p" do
      assert ContentUtils.plain_to_html(nil) == "<p></p>"
    end

    test "wraps empty string in empty p" do
      assert ContentUtils.plain_to_html("") == "<p></p>"
    end

    test "wraps text in p tags" do
      assert ContentUtils.plain_to_html("Hello world") == "<p>Hello world</p>"
    end

    test "converts newlines to separate paragraphs" do
      assert ContentUtils.plain_to_html("Line one\nLine two") == "<p>Line one</p><p>Line two</p>"
    end

    test "encodes special characters" do
      assert ContentUtils.plain_to_html("A & B < C") == "<p>A &amp; B &lt; C</p>"
    end
  end
end
