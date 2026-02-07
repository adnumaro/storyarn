defmodule StoryarnWeb.FlowLive.NodeTypeRegistryTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  describe "types/0" do
    test "returns all known node types" do
      types = NodeTypeRegistry.types()
      assert is_list(types)
      assert length(types) > 0
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

  for type <- ~w(entry exit dialogue hub condition instruction jump) do
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
      assert Map.has_key?(data, "input_condition")
      assert Map.has_key?(data, "output_instruction")
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
end
