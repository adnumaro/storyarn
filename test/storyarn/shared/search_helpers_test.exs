defmodule Storyarn.Shared.SearchHelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.SearchHelpers

  # ===========================================================================
  # sanitize_like_query/1
  # ===========================================================================

  describe "sanitize_like_query/1" do
    test "escapes percent wildcard" do
      assert SearchHelpers.sanitize_like_query("100%") == "100\\%"
    end

    test "escapes underscore wildcard" do
      assert SearchHelpers.sanitize_like_query("foo_bar") == "foo\\_bar"
    end

    test "escapes backslash" do
      assert SearchHelpers.sanitize_like_query("path\\to") == "path\\\\to"
    end

    test "escapes multiple wildcards" do
      assert SearchHelpers.sanitize_like_query("50% off_sale") == "50\\% off\\_sale"
    end

    test "handles string with no special characters" do
      assert SearchHelpers.sanitize_like_query("hello world") == "hello world"
    end

    test "handles empty string" do
      assert SearchHelpers.sanitize_like_query("") == ""
    end

    test "escapes all three special characters in sequence" do
      result = SearchHelpers.sanitize_like_query("\\%_")
      assert result == "\\\\\\%\\_"
    end

    test "preserves regular characters" do
      assert SearchHelpers.sanitize_like_query("simple query") == "simple query"
    end

    test "handles consecutive percent signs" do
      assert SearchHelpers.sanitize_like_query("%%") == "\\%\\%"
    end

    test "handles consecutive underscores" do
      assert SearchHelpers.sanitize_like_query("__init__") == "\\_\\_init\\_\\_"
    end

    test "handles backslash followed by wildcard" do
      # Backslash is escaped first, then percent
      assert SearchHelpers.sanitize_like_query("\\%") == "\\\\\\%"
    end

    test "handles Unicode characters" do
      assert SearchHelpers.sanitize_like_query("cafe%") == "cafe\\%"
    end
  end
end
