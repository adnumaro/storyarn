defmodule Storyarn.Exports.SerializerRegistryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.SerializerRegistry
  alias Storyarn.Exports.Serializers.ArticyXML
  alias Storyarn.Exports.Serializers.GodotDialogic
  alias Storyarn.Exports.Serializers.Ink
  alias Storyarn.Exports.Serializers.StoryarnJSON
  alias Storyarn.Exports.Serializers.UnityJSON
  alias Storyarn.Exports.Serializers.UnrealCSV
  alias Storyarn.Exports.Serializers.Yarn

  describe "get/1" do
    test "returns the storyarn serializer module" do
      assert {:ok, StoryarnJSON} = SerializerRegistry.get(:storyarn)
    end

    test "returns the ink serializer module" do
      assert {:ok, Ink} = SerializerRegistry.get(:ink)
    end

    test "returns the yarn serializer module" do
      assert {:ok, Yarn} = SerializerRegistry.get(:yarn)
    end

    test "returns the unity serializer module" do
      assert {:ok, UnityJSON} = SerializerRegistry.get(:unity)
    end

    test "returns the godot serializer module" do
      assert {:ok, GodotDialogic} = SerializerRegistry.get(:godot)
    end

    test "returns the unreal serializer module" do
      assert {:ok, UnrealCSV} = SerializerRegistry.get(:unreal)
    end

    test "returns the articy serializer module" do
      assert {:ok, ArticyXML} = SerializerRegistry.get(:articy)
    end

    test "returns error for unknown format" do
      assert {:error, {:unknown_format, :nonexistent}} = SerializerRegistry.get(:nonexistent)
    end
  end

  describe "list/0" do
    test "returns a map of all registered serializers" do
      serializers = SerializerRegistry.list()
      assert is_map(serializers)
      assert map_size(serializers) == 7

      assert serializers[:storyarn] == StoryarnJSON
      assert serializers[:ink] == Ink
      assert serializers[:yarn] == Yarn
      assert serializers[:unity] == UnityJSON
      assert serializers[:godot] == GodotDialogic
      assert serializers[:unreal] == UnrealCSV
      assert serializers[:articy] == ArticyXML
    end
  end

  describe "formats/0" do
    test "returns all format atoms" do
      formats = SerializerRegistry.formats()
      assert is_list(formats)
      assert length(formats) == 7
      assert :storyarn in formats
      assert :ink in formats
      assert :yarn in formats
      assert :unity in formats
      assert :godot in formats
      assert :unreal in formats
      assert :articy in formats
    end
  end

  describe "list_with_metadata/0" do
    test "returns metadata for all serializers in display order" do
      metadata = SerializerRegistry.list_with_metadata()
      assert is_list(metadata)
      assert length(metadata) == 7

      # Check display order (storyarn first)
      assert hd(metadata).format == :storyarn
    end

    test "each entry has required fields" do
      metadata = SerializerRegistry.list_with_metadata()

      for entry <- metadata do
        assert is_atom(entry.format)
        assert is_binary(entry.label)
        assert is_binary(entry.extension)
        assert is_binary(entry.content_type)
        assert is_list(entry.sections)
      end
    end

    test "storyarn entry has correct metadata" do
      [storyarn | _] = SerializerRegistry.list_with_metadata()

      assert storyarn.format == :storyarn
      assert is_binary(storyarn.label)
      assert storyarn.extension == "json"
      assert storyarn.content_type == "application/json"
    end

    test "display order matches: storyarn, ink, yarn, unity, godot, unreal, articy" do
      formats = Enum.map(SerializerRegistry.list_with_metadata(), & &1.format)
      assert formats == [:storyarn, :ink, :yarn, :unity, :godot, :unreal, :articy]
    end
  end
end
