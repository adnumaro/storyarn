defmodule Storyarn.Exports.SerializerRegistryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.SerializerRegistry
  alias Storyarn.Exports.Serializers.ArticyXML
  alias Storyarn.Exports.Serializers.GodotDialogic
  alias Storyarn.Exports.Serializers.Ink
  alias Storyarn.Exports.Serializers.UnityJSON
  alias Storyarn.Exports.Serializers.UnrealCSV
  alias Storyarn.Exports.Serializers.Yarn

  describe "get/1" do
    test "no longer resolves the removed storyarn format" do
      assert {:error, {:unknown_format, :storyarn}} = SerializerRegistry.get(:storyarn)
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
      assert map_size(serializers) == 6

      refute Map.has_key?(serializers, :storyarn)
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
      assert length(formats) == 6
      refute :storyarn in formats
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
      assert length(metadata) == 6

      # Check display order (ink first, now that storyarn is gone)
      assert hd(metadata).format == :ink
    end

    test "each entry has required fields" do
      metadata = SerializerRegistry.list_with_metadata()

      for entry <- metadata do
        assert is_atom(entry.format)
        assert is_binary(entry.label)
        assert is_binary(entry.extension)
        assert is_binary(entry.content_type)
        assert is_list(entry.sections)
        assert entry.localization_mode in [:embedded, :external_catalog]
      end
    end

    test "ink entry has correct metadata" do
      [ink | _] = SerializerRegistry.list_with_metadata()

      assert ink.format == :ink
      assert is_binary(ink.label)
      assert ink.extension == "ink"
      assert ink.localization_mode == :external_catalog
    end

    test "describes how every engine consumes localization" do
      modes = Map.new(SerializerRegistry.list_with_metadata(), &{&1.format, &1.localization_mode})

      assert modes == %{
               ink: :external_catalog,
               yarn: :external_catalog,
               unity: :embedded,
               godot: :external_catalog,
               unreal: :external_catalog,
               articy: :external_catalog
             }
    end

    test "display order matches: ink, yarn, unity, godot, unreal, articy" do
      formats = Enum.map(SerializerRegistry.list_with_metadata(), & &1.format)
      assert formats == [:ink, :yarn, :unity, :godot, :unreal, :articy]
    end
  end
end
