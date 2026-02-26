defmodule StoryarnWeb.ScreenplayLive.Helpers.SocketHelpersTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers

  # ── valid_dual_sides/0 ──────────────────────────────────────────────

  describe "valid_dual_sides/0" do
    test "returns left and right" do
      assert SocketHelpers.valid_dual_sides() == ~w(left right)
    end
  end

  # ── valid_dual_fields/0 ─────────────────────────────────────────────

  describe "valid_dual_fields/0" do
    test "returns character, parenthetical, dialogue" do
      assert SocketHelpers.valid_dual_fields() == ~w(character parenthetical dialogue)
    end
  end

  # ── valid_title_fields/0 ────────────────────────────────────────────

  describe "valid_title_fields/0" do
    test "returns expected title fields" do
      result = SocketHelpers.valid_title_fields()
      assert "title" in result
      assert "credit" in result
      assert "author" in result
      assert "draft_date" in result
      assert "contact" in result
      assert length(result) == 5
    end
  end

  # ── sanitize_plain_text/1 ──────────────────────────────────────────

  describe "sanitize_plain_text/1" do
    test "strips HTML tags from string" do
      assert SocketHelpers.sanitize_plain_text("<p>Hello <b>world</b></p>") == "Hello world"
    end

    test "returns plain text as-is" do
      assert SocketHelpers.sanitize_plain_text("Hello world") == "Hello world"
    end

    test "returns empty string for nil" do
      assert SocketHelpers.sanitize_plain_text(nil) == ""
    end

    test "returns empty string for non-binary" do
      assert SocketHelpers.sanitize_plain_text(42) == ""
    end

    test "returns empty string for atom" do
      assert SocketHelpers.sanitize_plain_text(:not_text) == ""
    end

    test "handles empty string" do
      assert SocketHelpers.sanitize_plain_text("") == ""
    end

    test "strips nested HTML" do
      result = SocketHelpers.sanitize_plain_text("<div><p>inner</p></div>")
      assert result == "inner"
    end
  end

  # ── parse_int/1 (delegated to MapUtils) ────────────────────────────

  describe "parse_int/1" do
    test "parses string integer" do
      assert SocketHelpers.parse_int("42") == 42
    end

    test "returns integer as-is" do
      assert SocketHelpers.parse_int(42) == 42
    end

    test "returns nil for nil" do
      assert SocketHelpers.parse_int(nil) == nil
    end
  end
end
