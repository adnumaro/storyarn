defmodule Storyarn.Scenes.PositionUtils do
  @moduledoc """
  Shared position utilities for map elements.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneLayer

  @doc "Serializes position allocation for all elements belonging to a scene."
  def with_scene_lock(scene_id, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      Repo.one!(from(scene in Scene, where: scene.id == ^scene_id, lock: "FOR UPDATE"))

      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Locks and validates the requested layer for a scene mutation.

  The caller must already be inside the scene-root transaction established by
  `with_scene_lock/2`. Missing `layer_id` attributes preserve the current layer;
  explicit `nil` detaches the element from its layer.
  """
  def lock_requested_layer_for_scene(scene_id, attrs, current_layer_id \\ nil) when is_map(attrs) do
    layer_id =
      cond do
        Map.has_key?(attrs, "layer_id") -> Map.get(attrs, "layer_id")
        Map.has_key?(attrs, :layer_id) -> Map.get(attrs, :layer_id)
        true -> current_layer_id
      end

    lock_layer_for_scene(scene_id, normalize_layer_id(layer_id))
  end

  defp lock_layer_for_scene(_scene_id, nil), do: :ok

  defp lock_layer_for_scene(_scene_id, {:invalid, layer_id}), do: {:error, {:invalid_scene_layer_id, layer_id}}

  defp lock_layer_for_scene(scene_id, layer_id) do
    case Repo.one(
           from(layer in SceneLayer,
             where: layer.id == ^layer_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SceneLayer{scene_id: ^scene_id} ->
        :ok

      %SceneLayer{scene_id: owner_scene_id} ->
        {:error, {:scene_layer_ownership_mismatch, layer_id, scene_id, owner_scene_id}}

      nil ->
        {:error, {:scene_layer_not_found, layer_id}}
    end
  end

  defp normalize_layer_id(nil), do: nil
  defp normalize_layer_id(""), do: nil
  defp normalize_layer_id(layer_id) when is_integer(layer_id) and layer_id > 0, do: layer_id

  defp normalize_layer_id(layer_id) when is_binary(layer_id) do
    case Integer.parse(layer_id) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> {:invalid, layer_id}
    end
  end

  defp normalize_layer_id(layer_id), do: {:invalid, layer_id}

  @doc """
  Returns the next position value for a schema's items within a map.
  Equivalent to MAX(position) + 1, or 0 if no items exist.
  """
  def next_position(schema, scene_id) do
    from(x in schema, where: x.scene_id == ^scene_id, select: max(x.position))
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
