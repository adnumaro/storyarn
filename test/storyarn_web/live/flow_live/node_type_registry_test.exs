defmodule StoryarnWeb.FlowLive.NodeTypeRegistryTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  describe "types/0" do
    test "returns all known node types" do
      types = NodeTypeRegistry.types()
      assert is_list(types)
      assert [_ | _] = types
      assert "dialogue" in types
      assert "condition" in types
      assert "entry" in types
    end
  end

  describe "user_addable_types/0" do
    test "excludes entry from addable types" do
      types = NodeTypeRegistry.user_addable_types()
      refute "entry" in types
      assert "dialogue" in types
      assert "condition" in types
    end

    test "is a subset of types" do
      all = NodeTypeRegistry.types()
      addable = NodeTypeRegistry.user_addable_types()
      assert Enum.all?(addable, &(&1 in all))
    end
  end

  for type <- ~w(entry exit dialogue hub condition instruction jump scene subflow) do
    describe "icon_name/1 for #{type}" do
      test "returns a non-empty string" do
        result = NodeTypeRegistry.icon_name(unquote(type))
        assert is_binary(result)
        assert result != ""
      end
    end

    describe "label/1 for #{type}" do
      test "returns a non-empty string" do
        result = NodeTypeRegistry.label(unquote(type))
        assert is_binary(result)
        assert result != ""
      end
    end

    describe "default_data/1 for #{type}" do
      test "returns a map" do
        result = NodeTypeRegistry.default_data(unquote(type))
        assert is_map(result)
      end
    end

    describe "extract_form_data/2 for #{type}" do
      test "returns a map given default data" do
        data = NodeTypeRegistry.default_data(unquote(type))
        result = NodeTypeRegistry.extract_form_data(unquote(type), data)
        assert is_map(result)
      end
    end
  end

  describe "icon_name/1 for unknown type" do
    test "returns a fallback" do
      assert NodeTypeRegistry.icon_name("unknown") == "circle"
    end
  end

  describe "dialogue default_data details" do
    test "includes all required fields" do
      data = NodeTypeRegistry.default_data("dialogue")

      assert Map.has_key?(data, "speaker_sheet_id")
      assert Map.has_key?(data, "text")
      assert Map.has_key?(data, "stage_directions")
      assert Map.has_key?(data, "menu_text")
      assert Map.has_key?(data, "audio_asset_id")
      assert Map.has_key?(data, "technical_id")
      assert Map.has_key?(data, "localization_id")
      assert Map.has_key?(data, "responses")
      assert is_list(data["responses"])
    end

    test "generates a unique localization_id" do
      data1 = NodeTypeRegistry.default_data("dialogue")
      data2 = NodeTypeRegistry.default_data("dialogue")
      assert data1["localization_id"] != data2["localization_id"]
    end
  end

  describe "condition default_data details" do
    test "includes condition and switch_mode" do
      data = NodeTypeRegistry.default_data("condition")

      assert Map.has_key?(data, "condition")
      assert Map.has_key?(data, "switch_mode")
      assert data["condition"]["logic"] == "all"
      assert data["condition"]["rules"] == []
      assert data["switch_mode"] == false
    end
  end

  describe "dialogue extract_form_data details" do
    test "preserves existing values and defaults missing ones" do
      data = %{
        "speaker_sheet_id" => "123",
        "text" => "<p>Hello</p>",
        "responses" => [%{"id" => "r1", "text" => "Hi"}]
      }

      result = NodeTypeRegistry.extract_form_data("dialogue", data)

      assert result["speaker_sheet_id"] == "123"
      assert result["text"] == "<p>Hello</p>"
      assert result["responses"] == [%{"id" => "r1", "text" => "Hi"}]
      # Missing fields get defaults
      assert result["stage_directions"] == ""
      assert result["menu_text"] == ""
      assert result["technical_id"] == ""
    end
  end

  describe "unknown type extract_form_data" do
    test "returns empty map" do
      assert NodeTypeRegistry.extract_form_data("unknown", %{"foo" => "bar"}) == %{}
    end
  end

  # ===========================================================================
  # node_module/1
  # ===========================================================================

  describe "node_module/1" do
    test "returns a module for each valid type" do
      for type <- ~w(entry exit dialogue hub condition instruction jump scene subflow) do
        mod = NodeTypeRegistry.node_module(type)
        assert is_atom(mod) and mod != nil, "Expected module for #{type}"
      end
    end

    test "returns nil for unknown type" do
      assert NodeTypeRegistry.node_module("nonexistent") == nil
    end

    test "returns nil for empty string" do
      assert NodeTypeRegistry.node_module("") == nil
    end
  end

  # ===========================================================================
  # label/1 — fallback
  # ===========================================================================

  describe "label/1 for unknown type" do
    test "returns the type string itself" do
      assert NodeTypeRegistry.label("unknown_type") == "unknown_type"
    end
  end

  # ===========================================================================
  # default_data/1 — fallback
  # ===========================================================================

  describe "default_data/1 for unknown type" do
    test "returns empty map" do
      assert NodeTypeRegistry.default_data("unknown") == %{}
    end
  end

  # ===========================================================================
  # on_double_click/2
  # ===========================================================================

  describe "on_double_click/2" do
    for type <- ~w(entry exit dialogue hub condition instruction jump scene subflow) do
      test "returns valid action for #{type}" do
        data = NodeTypeRegistry.default_data(unquote(type))
        node = %{type: unquote(type), data: data}
        result = NodeTypeRegistry.on_double_click(unquote(type), node)

        assert result in [:toolbar, :editor, :builder] or match?({:navigate, _}, result),
               "Unexpected result for #{unquote(type)}: #{inspect(result)}"
      end
    end

    test "returns :toolbar for unknown type" do
      assert NodeTypeRegistry.on_double_click("unknown", %{}) == :toolbar
    end
  end

  # ===========================================================================
  # on_select/3
  # ===========================================================================

  describe "on_select/3" do
    test "returns socket unchanged for unknown type" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      assert NodeTypeRegistry.on_select("unknown", %{}, socket) == socket
    end
  end

  # ===========================================================================
  # duplicate_data_cleanup/2
  # ===========================================================================

  describe "duplicate_data_cleanup/2" do
    for type <- ~w(entry exit dialogue hub condition instruction jump scene subflow) do
      test "returns a map for #{type}" do
        data = NodeTypeRegistry.default_data(unquote(type))
        result = NodeTypeRegistry.duplicate_data_cleanup(unquote(type), data)
        assert is_map(result)
      end
    end

    test "returns data unchanged for unknown type" do
      data = %{"foo" => "bar"}
      assert NodeTypeRegistry.duplicate_data_cleanup("unknown", data) == data
    end

    test "dialogue cleanup clears unique identifiers" do
      data = %{
        "text" => "hello",
        "localization_id" => "loc_123",
        "technical_id" => "tech_1",
        "responses" => []
      }

      result = NodeTypeRegistry.duplicate_data_cleanup("dialogue", data)
      assert result["localization_id"] != "loc_123"
      assert result["technical_id"] != "tech_1"
    end
  end
end
