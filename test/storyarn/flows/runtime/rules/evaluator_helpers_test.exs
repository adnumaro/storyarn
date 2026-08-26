defmodule Storyarn.Flows.Evaluator.HelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.Helpers

  describe "strip_html/2" do
    test "returns nil for nil input" do
      assert Helpers.strip_html(nil) == nil
    end

    test "strips HTML tags from text" do
      assert Helpers.strip_html("<p>Hello <strong>world</strong></p>") == "Hello world"
    end

    test "trims whitespace" do
      assert Helpers.strip_html("  Hello  ") == "Hello"
    end

    test "returns nil for empty string" do
      assert Helpers.strip_html("") == nil
    end

    test "returns nil for HTML-only content (tags with no text)" do
      assert Helpers.strip_html("<br><hr>") == nil
    end

    test "truncates to default 40 characters" do
      long_text = String.duplicate("a", 50)
      result = Helpers.strip_html(long_text)
      assert String.length(result) == 40
    end

    test "truncates to custom max_length" do
      result = Helpers.strip_html("Hello World", 5)
      assert result == "Hello"
    end

    test "does not truncate short text" do
      assert Helpers.strip_html("Short") == "Short"
    end

    test "handles nested HTML tags" do
      html = "<div><p><em>nested</em> <strong>content</strong></p></div>"
      assert Helpers.strip_html(html) == "nested content"
    end

    test "handles whitespace-only content after stripping tags" do
      assert Helpers.strip_html("<p>   </p>") == nil
    end
  end

  describe "format_value/1" do
    test "formats nil" do
      assert Helpers.format_value(nil) == "nil"
    end

    test "formats true" do
      assert Helpers.format_value(true) == "true"
    end

    test "formats false" do
      assert Helpers.format_value(false) == "false"
    end

    test "formats a list by joining with commas" do
      assert Helpers.format_value(["a", "b", "c"]) == "a, b, c"
    end

    test "formats an empty list" do
      assert Helpers.format_value([]) == ""
    end

    test "formats a short string as-is" do
      assert Helpers.format_value("hello") == "hello"
    end

    test "truncates a long string to 30 chars with ellipsis" do
      long = String.duplicate("x", 40)
      result = Helpers.format_value(long)
      assert result == String.duplicate("x", 30) <> "..."
    end

    test "does not truncate a string exactly 30 chars" do
      str = String.duplicate("x", 30)
      assert Helpers.format_value(str) == str
    end

    test "formats an integer" do
      assert Helpers.format_value(42) == "42"
    end

    test "formats a float" do
      assert Helpers.format_value(3.14) == "3.14"
    end

    test "formats an atom" do
      assert Helpers.format_value(:hello) == "hello"
    end
  end
end
