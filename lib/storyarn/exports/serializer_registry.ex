defmodule Storyarn.Exports.SerializerRegistry do
  @moduledoc """
  Registry mapping format atoms to serializer modules.

  Adding a new engine format requires only a new module implementing
  `Storyarn.Exports.Serializer` and one entry here.
  """

  @serializers %{
    storyarn: Storyarn.Exports.Serializers.StoryarnJSON
  }

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
end
