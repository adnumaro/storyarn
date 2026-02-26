defmodule Storyarn.Exports.SerializerRegistry do
  @moduledoc """
  Registry mapping format atoms to serializer modules.

  Adding a new engine format requires only a new module implementing
  `Storyarn.Exports.Serializer` and one entry here.
  """

  @display_order [
    :storyarn,
    :ink,
    :yarn,
    :unity,
    :godot,
    :unreal,
    :articy
  ]

  @serializers %{
    storyarn: Storyarn.Exports.Serializers.StoryarnJSON,
    ink: Storyarn.Exports.Serializers.Ink,
    yarn: Storyarn.Exports.Serializers.Yarn,
    unity: Storyarn.Exports.Serializers.UnityJSON,
    godot: Storyarn.Exports.Serializers.GodotJSON,
    unreal: Storyarn.Exports.Serializers.UnrealCSV,
    articy: Storyarn.Exports.Serializers.ArticyXML
  }

  if MapSet.new(@display_order) != MapSet.new(Map.keys(@serializers)) do
    raise CompileError,
      description: "SerializerRegistry: @display_order and @serializers keys are out of sync"
  end

  @doc """
  Get the serializer module for a format atom.

  Returns `{:ok, module}` or `{:error, {:unknown_format, atom}}`.
  """
  def get(format) when is_atom(format) do
    case Map.fetch(@serializers, format) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_format, format}}
    end
  end

  @doc """
  List all registered serializers as a map of `%{format => module}`.
  """
  def list, do: @serializers

  @doc """
  List all available format atoms.
  """
  def formats, do: Map.keys(@serializers)

  @doc """
  List all formats with their display metadata.

  Returns a list of maps sorted by display order:
  `[%{format: :storyarn, label: "Storyarn JSON", extension: "json", sections: [...]}]`
  """
  def list_with_metadata do
    @display_order
    |> Enum.map(fn format ->
      module = Map.fetch!(@serializers, format)

      %{
        format: format,
        label: module.format_label(),
        extension: module.file_extension(),
        content_type: module.content_type(),
        sections: module.supported_sections()
      }
    end)
  end
end
