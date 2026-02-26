defmodule StoryarnWeb.SceneLive.Helpers.SceneHelpersTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.SceneLive.Helpers.SceneHelpers

  # ── matches_text?/2 ──────────────────────────────────────────────────

  describe "matches_text?/2" do
    test "returns true when text contains query" do
      assert SceneHelpers.matches_text?("Castle Gate", "castle")
    end

    test "is case insensitive" do
      assert SceneHelpers.matches_text?("Castle", "castle")
    end

    test "returns false when text does not contain query" do
      refute SceneHelpers.matches_text?("Castle", "dungeon")
    end

    test "returns false for nil text" do
      refute SceneHelpers.matches_text?(nil, "anything")
    end

    test "returns true for empty query (contained in everything)" do
      assert SceneHelpers.matches_text?("anything", "")
    end
  end

  # ── search_result_icon/1 ─────────────────────────────────────────────

  describe "search_result_icon/1" do
    test "pin returns map-pin" do
      assert SceneHelpers.search_result_icon("pin") == "map-pin"
    end

    test "zone returns pentagon" do
      assert SceneHelpers.search_result_icon("zone") == "pentagon"
    end

    test "connection returns cable" do
      assert SceneHelpers.search_result_icon("connection") == "cable"
    end

    test "annotation returns sticky-note" do
      assert SceneHelpers.search_result_icon("annotation") == "sticky-note"
    end

    test "unknown type returns search" do
      assert SceneHelpers.search_result_icon("unknown") == "search"
    end
  end

  # ── parse_id/1 ───────────────────────────────────────────────────────

  describe "parse_id/1" do
    test "returns integer as-is" do
      assert SceneHelpers.parse_id(42) == 42
    end

    test "parses string to integer" do
      assert SceneHelpers.parse_id("42") == 42
    end

    test "returns original string for non-numeric" do
      assert SceneHelpers.parse_id("abc") == "abc"
    end

    test "returns original string for partial number" do
      assert SceneHelpers.parse_id("42abc") == "42abc"
    end

    test "parses negative number" do
      assert SceneHelpers.parse_id("-5") == -5
    end
  end

  # ── parse_float/1-2 ─────────────────────────────────────────────────

  describe "parse_float/1-2" do
    test "parses float string" do
      assert SceneHelpers.parse_float("3.14") == 3.14
    end

    test "parses integer string as float" do
      assert SceneHelpers.parse_float("42") == 42.0
    end

    test "returns float as-is" do
      assert SceneHelpers.parse_float(3.14) == 3.14
    end

    test "returns integer converted to float" do
      assert SceneHelpers.parse_float(42) == 42.0
    end

    test "returns default for empty string" do
      assert SceneHelpers.parse_float("") == 0.85
    end

    test "returns default for nil" do
      assert SceneHelpers.parse_float(nil) == 0.85
    end

    test "returns custom default for empty string" do
      assert SceneHelpers.parse_float("", 1.0) == 1.0
    end

    test "returns custom default for nil" do
      assert SceneHelpers.parse_float(nil, 2.0) == 2.0
    end

    test "returns default for non-numeric type" do
      assert SceneHelpers.parse_float(:atom) == 0.85
    end

    test "parses negative float" do
      assert SceneHelpers.parse_float("-1.5") == -1.5
    end

    test "parses string with trailing text" do
      assert SceneHelpers.parse_float("3.14abc") == 3.14
    end
  end

  # ── parse_float_or_nil/1 ────────────────────────────────────────────

  describe "parse_float_or_nil/1" do
    test "parses valid float string" do
      assert SceneHelpers.parse_float_or_nil("1.5") == 1.5
    end

    test "returns nil for empty string" do
      assert SceneHelpers.parse_float_or_nil("") == nil
    end

    test "returns nil for nil" do
      assert SceneHelpers.parse_float_or_nil(nil) == nil
    end
  end

  # ── parse_scale_field/2 ─────────────────────────────────────────────

  describe "parse_scale_field/2" do
    test "parses valid positive number for scale_value field" do
      assert SceneHelpers.parse_scale_field("scale_value", "5.0") == 5.0
    end

    test "returns nil for zero scale_value" do
      assert SceneHelpers.parse_scale_field("scale_value", "0") == nil
    end

    test "returns nil for negative scale_value" do
      assert SceneHelpers.parse_scale_field("scale_value", "-1.0") == nil
    end

    test "returns nil for non-numeric scale_value" do
      assert SceneHelpers.parse_scale_field("scale_value", "") == nil
    end

    test "passes through value for non-scale_value field" do
      assert SceneHelpers.parse_scale_field("other_field", "anything") == "anything"
    end
  end

  # ── extract_field_value/2 ───────────────────────────────────────────

  describe "extract_field_value/2" do
    test "extracts toggle value when present" do
      params = %{"toggle" => true}
      assert SceneHelpers.extract_field_value(params, "visible") == true
    end

    test "extracts value key when present" do
      params = %{"value" => "hello"}
      assert SceneHelpers.extract_field_value(params, "name") == "hello"
    end

    test "extracts field-named value when no toggle or value" do
      params = %{"name" => "Castle"}
      assert SceneHelpers.extract_field_value(params, "name") == "Castle"
    end

    test "falls back to empty string when field not found" do
      params = %{"other" => "data"}
      assert SceneHelpers.extract_field_value(params, "name") == ""
    end

    test "toggle takes precedence over value" do
      params = %{"toggle" => false, "value" => "ignored"}
      assert SceneHelpers.extract_field_value(params, "field") == false
    end
  end

  # ── replace_in_list/2 and replace_element/2 ─────────────────────────

  describe "replace_in_list/2" do
    test "replaces matching element by id" do
      list = [%{id: 1, name: "old"}, %{id: 2, name: "keep"}]
      updated = %{id: 1, name: "new"}
      result = SceneHelpers.replace_in_list(list, updated)

      assert Enum.at(result, 0).name == "new"
      assert Enum.at(result, 1).name == "keep"
    end

    test "handles list where no element matches" do
      list = [%{id: 1, name: "a"}, %{id: 2, name: "b"}]
      updated = %{id: 99, name: "missing"}
      result = SceneHelpers.replace_in_list(list, updated)

      assert result == list
    end

    test "handles empty list" do
      assert SceneHelpers.replace_in_list([], %{id: 1}) == []
    end
  end

  describe "replace_element/2" do
    test "returns updated when IDs match" do
      element = %{id: 1, name: "old"}
      updated = %{id: 1, name: "new"}
      assert SceneHelpers.replace_element(element, updated) == updated
    end

    test "returns original when IDs differ" do
      element = %{id: 1, name: "keep"}
      updated = %{id: 2, name: "other"}
      assert SceneHelpers.replace_element(element, updated) == element
    end
  end

  # ── panel_icon/1 ────────────────────────────────────────────────────

  describe "panel_icon/1" do
    test "pin returns map-pin" do
      assert SceneHelpers.panel_icon("pin") == "map-pin"
    end

    test "zone returns pentagon" do
      assert SceneHelpers.panel_icon("zone") == "pentagon"
    end

    test "connection returns cable" do
      assert SceneHelpers.panel_icon("connection") == "cable"
    end

    test "annotation returns sticky-note" do
      assert SceneHelpers.panel_icon("annotation") == "sticky-note"
    end

    test "unknown returns settings" do
      assert SceneHelpers.panel_icon("unknown") == "settings"
    end
  end

  # ── panel_title/1 ───────────────────────────────────────────────────

  describe "panel_title/1" do
    test "returns a string for each known type" do
      for type <- ~w(pin zone connection annotation) do
        assert is_binary(SceneHelpers.panel_title(type))
      end
    end

    test "returns Properties for unknown type" do
      assert is_binary(SceneHelpers.panel_title("unknown"))
    end
  end

  # ── flatten_sheets/1 ────────────────────────────────────────────────

  describe "flatten_sheets/1" do
    test "flattens nested sheet tree" do
      sheets = [
        %{
          id: 1,
          name: "Parent",
          children: [
            %{id: 2, name: "Child", children: []}
          ]
        },
        %{id: 3, name: "Other", children: []}
      ]

      result = SceneHelpers.flatten_sheets(sheets)

      assert length(result) == 3
      ids = Enum.map(result, & &1.id)
      assert ids == [1, 2, 3]
    end

    test "handles sheets without children key" do
      sheets = [%{id: 1, name: "Solo"}]
      result = SceneHelpers.flatten_sheets(sheets)

      assert length(result) == 1
    end

    test "returns empty list for empty input" do
      assert SceneHelpers.flatten_sheets([]) == []
    end

    test "handles deeply nested tree" do
      sheets = [
        %{
          id: 1,
          children: [
            %{
              id: 2,
              children: [
                %{id: 3, children: []}
              ]
            }
          ]
        }
      ]

      result = SceneHelpers.flatten_sheets(sheets)
      assert length(result) == 3
    end
  end

  # ── sheet_avatar_url/1 ──────────────────────────────────────────────

  describe "sheet_avatar_url/1" do
    test "extracts url from nested avatar_asset" do
      sheet = %{avatar_asset: %{url: "https://cdn.test/avatar.png"}}
      assert SceneHelpers.sheet_avatar_url(sheet) == "https://cdn.test/avatar.png"
    end

    test "returns nil for nil avatar_asset" do
      assert SceneHelpers.sheet_avatar_url(%{avatar_asset: nil}) == nil
    end

    test "returns nil for missing avatar_asset" do
      assert SceneHelpers.sheet_avatar_url(%{}) == nil
    end

    test "returns nil for nil url" do
      assert SceneHelpers.sheet_avatar_url(%{avatar_asset: %{url: nil}}) == nil
    end
  end

  # ── search_pins/2, search_zones/2, search_annotations/2, search_connections/2 ──

  describe "search_pins/2" do
    test "filters pins by label match" do
      pins = [
        %{id: 1, label: "Castle Gate"},
        %{id: 2, label: "Tavern"},
        %{id: 3, label: nil}
      ]

      result = SceneHelpers.search_pins(pins, "castle")

      assert length(result) == 1
      assert hd(result).id == 1
      assert hd(result).type == "pin"
    end

    test "returns empty list when no match" do
      pins = [%{id: 1, label: "Gate"}]
      assert SceneHelpers.search_pins(pins, "dungeon") == []
    end
  end

  describe "search_zones/2" do
    test "filters zones by name match" do
      zones = [
        %{id: 1, name: "Forest"},
        %{id: 2, name: "Desert"}
      ]

      result = SceneHelpers.search_zones(zones, "forest")

      assert length(result) == 1
      assert hd(result).type == "zone"
    end
  end

  describe "search_annotations/2" do
    test "filters annotations by text match" do
      annotations = [
        %{id: 1, text: "Important note"},
        %{id: 2, text: "TODO: fix later"}
      ]

      result = SceneHelpers.search_annotations(annotations, "important")

      assert length(result) == 1
      assert hd(result).type == "annotation"
    end
  end

  describe "search_connections/2" do
    test "filters connections by label match" do
      connections = [
        %{id: 1, label: "Path to castle"},
        %{id: 2, label: "Road to town"}
      ]

      result = SceneHelpers.search_connections(connections, "castle")

      assert length(result) == 1
      assert hd(result).type == "connection"
    end
  end
end
