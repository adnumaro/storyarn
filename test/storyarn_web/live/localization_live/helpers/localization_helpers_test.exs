defmodule StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpersTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers

  # ── maybe_add/3 ──────────────────────────────────────────────────────

  describe "maybe_add/3" do
    test "does not add nil value" do
      opts = [locale_code: "en"]
      assert LocalizationHelpers.maybe_add(opts, :status, nil) == opts
    end

    test "adds non-nil value" do
      opts = [locale_code: "en"]
      result = LocalizationHelpers.maybe_add(opts, :status, "pending")

      assert Keyword.get(result, :status) == "pending"
      assert Keyword.get(result, :locale_code) == "en"
    end

    test "adds false value (not nil)" do
      opts = []
      result = LocalizationHelpers.maybe_add(opts, :active, false)

      assert Keyword.get(result, :active) == false
    end

    test "adds empty string (not nil)" do
      opts = []
      result = LocalizationHelpers.maybe_add(opts, :search, "")

      assert Keyword.get(result, :search) == ""
    end

    test "replaces existing key" do
      opts = [status: "old"]
      result = LocalizationHelpers.maybe_add(opts, :status, "new")

      assert Keyword.get(result, :status) == "new"
    end
  end

  # ── non_blank/1 ──────────────────────────────────────────────────────

  describe "non_blank/1" do
    test "returns nil for empty string" do
      assert LocalizationHelpers.non_blank("") == nil
    end

    test "returns string for non-empty string" do
      assert LocalizationHelpers.non_blank("hello") == "hello"
    end

    test "returns whitespace string (only empty string is blank)" do
      assert LocalizationHelpers.non_blank(" ") == " "
    end
  end

  # ── status_label/1 ──────────────────────────────────────────────────

  describe "status_label/1" do
    test "pending" do
      assert LocalizationHelpers.status_label("pending") == "Pending"
    end

    test "draft" do
      assert LocalizationHelpers.status_label("draft") == "Draft"
    end

    test "in_progress" do
      assert LocalizationHelpers.status_label("in_progress") == "In Progress"
    end

    test "review" do
      assert LocalizationHelpers.status_label("review") == "Review"
    end

    test "final" do
      assert LocalizationHelpers.status_label("final") == "Final"
    end

    test "unknown status returns itself" do
      assert LocalizationHelpers.status_label("unknown") == "unknown"
    end
  end

  # ── status_class/1 ──────────────────────────────────────────────────

  describe "status_class/1" do
    test "pending returns badge-ghost" do
      assert LocalizationHelpers.status_class("pending") == "badge-ghost"
    end

    test "draft returns badge-warning" do
      assert LocalizationHelpers.status_class("draft") == "badge-warning"
    end

    test "in_progress returns badge-info" do
      assert LocalizationHelpers.status_class("in_progress") == "badge-info"
    end

    test "review returns badge-secondary" do
      assert LocalizationHelpers.status_class("review") == "badge-secondary"
    end

    test "final returns badge-success" do
      assert LocalizationHelpers.status_class("final") == "badge-success"
    end

    test "unknown returns badge-ghost" do
      assert LocalizationHelpers.status_class("anything") == "badge-ghost"
    end
  end

  # ── source_type_label/1 ─────────────────────────────────────────────

  describe "source_type_label/1" do
    test "flow_node" do
      assert LocalizationHelpers.source_type_label("flow_node") == "Node"
    end

    test "block" do
      assert LocalizationHelpers.source_type_label("block") == "Block"
    end

    test "sheet" do
      assert LocalizationHelpers.source_type_label("sheet") == "Sheet"
    end

    test "flow" do
      assert LocalizationHelpers.source_type_label("flow") == "Flow"
    end

    test "screenplay" do
      assert LocalizationHelpers.source_type_label("screenplay") == "Screenplay"
    end

    test "unknown returns itself" do
      assert LocalizationHelpers.source_type_label("custom") == "custom"
    end
  end

  # ── source_type_icon/1 ──────────────────────────────────────────────

  describe "source_type_icon/1" do
    test "flow_node returns message-square" do
      assert LocalizationHelpers.source_type_icon("flow_node") == "message-square"
    end

    test "block returns square" do
      assert LocalizationHelpers.source_type_icon("block") == "square"
    end

    test "sheet returns file-text" do
      assert LocalizationHelpers.source_type_icon("sheet") == "file-text"
    end

    test "flow returns git-branch" do
      assert LocalizationHelpers.source_type_icon("flow") == "git-branch"
    end

    test "screenplay returns clapperboard" do
      assert LocalizationHelpers.source_type_icon("screenplay") == "clapperboard"
    end

    test "unknown returns box" do
      assert LocalizationHelpers.source_type_icon("custom") == "box"
    end
  end
end
