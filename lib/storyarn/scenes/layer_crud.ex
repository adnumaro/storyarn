defmodule Storyarn.Scenes.LayerCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.PositionUtils
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneReferenceIntegrity
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.TreeOperations

  @doc """
  Lists all layers for a map, ordered by position.
  """
  def list_layers(scene_id) do
    Repo.all(from(l in SceneLayer, where: l.scene_id == ^scene_id, order_by: [asc: l.position]))
  end

  def get_layer(scene_id, layer_id) do
    Repo.one(from(l in SceneLayer, where: l.scene_id == ^scene_id and l.id == ^layer_id))
  end

  def get_layer!(scene_id, layer_id) do
    Repo.one!(from(l in SceneLayer, where: l.scene_id == ^scene_id and l.id == ^layer_id))
  end

  def create_layer(scene_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    SceneReferenceIntegrity.with_active_scene_lock(scene_id, fn scene ->
      position = PositionUtils.next_position(SceneLayer, scene.id)

      %SceneLayer{scene_id: scene.id}
      |> SceneLayer.create_changeset(Map.put(attrs, "position", position))
      |> Repo.insert()
    end)
  end

  def update_layer(%SceneLayer{} = layer, attrs) do
    SceneReferenceIntegrity.with_active_scene_lock(layer.scene_id, fn scene ->
      with {:ok, locked_layer} <- lock_layer_for_scene(layer.id, scene.id) do
        locked_layer
        |> SceneLayer.update_changeset(attrs)
        |> Repo.update()
      end
    end)
  end

  @doc """
  Toggles the visibility of a layer.
  """
  def toggle_layer_visibility(%SceneLayer{} = layer) do
    SceneReferenceIntegrity.with_active_scene_lock(layer.scene_id, fn scene ->
      with {:ok, locked_layer} <- lock_layer_for_scene(layer.id, scene.id) do
        locked_layer
        |> Ecto.Changeset.change(visible: !locked_layer.visible)
        |> Repo.update()
      end
    end)
  end

  @doc """
  Deletes a layer. Prevents deleting the last layer in a map.
  When deleted, zones and pins on this layer have their layer_id set to nil (via FK nilify_all).
  """
  def delete_layer(%SceneLayer{} = layer) do
    SceneReferenceIntegrity.with_active_scene_lock(layer.scene_id, fn scene ->
      layers = lock_layers_for_scene(scene.id)
      delete_locked_layer(layers, layer.id)
    end)
  end

  defp delete_locked_layer(layers, layer_id) do
    with {:ok, locked_layer} <- find_locked_layer(layers, layer_id),
         :ok <- ensure_layer_can_be_deleted(layers) do
      do_delete_layer(locked_layer)
    end
  end

  defp ensure_layer_can_be_deleted([_last_layer]), do: {:error, :cannot_delete_last_layer}
  defp ensure_layer_can_be_deleted(_layers), do: :ok

  defp do_delete_layer(layer) do
    Repo.update_all(from(z in SceneZone, where: z.layer_id == ^layer.id), set: [layer_id: nil])
    Repo.update_all(from(p in ScenePin, where: p.layer_id == ^layer.id), set: [layer_id: nil])
    Repo.update_all(from(a in SceneAnnotation, where: a.layer_id == ^layer.id), set: [layer_id: nil])

    Repo.delete(layer)
  end

  @doc """
  Reorders layers by updating positions in a transaction.
  """
  def reorder_layers(scene_id, layer_ids) when is_list(layer_ids) do
    SceneReferenceIntegrity.with_active_scene_lock(scene_id, fn scene ->
      with {:ok, normalized_ids} <-
             normalize_reorder_ids(layer_ids),
           :ok <- lock_requested_layers(scene.id, normalized_ids) do
        TreeOperations.batch_set_positions(
          "scene_layers",
          Enum.with_index(normalized_ids),
          scope: {"scene_id", scene.id}
        )

        {:ok, list_layers(scene.id)}
      end
    end)
  end

  def change_layer(%SceneLayer{} = layer, attrs \\ %{}) do
    SceneLayer.update_changeset(layer, attrs)
  end

  defp lock_layer_for_scene(layer_id, scene_id) do
    case Repo.one(
           from(layer in SceneLayer,
             where: layer.id == ^layer_id and layer.scene_id == ^scene_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SceneLayer{} = layer -> {:ok, layer}
      nil -> {:error, :layer_not_found}
    end
  end

  defp lock_layers_for_scene(scene_id) do
    Repo.all(
      from(layer in SceneLayer,
        where: layer.scene_id == ^scene_id,
        order_by: [asc: layer.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp find_locked_layer(layers, layer_id) do
    case Enum.find(layers, &(&1.id == layer_id)) do
      %SceneLayer{} = layer -> {:ok, layer}
      nil -> {:error, :layer_not_found}
    end
  end

  defp lock_requested_layers(_scene_id, []), do: :ok

  defp lock_requested_layers(scene_id, layer_ids) do
    locked_ids =
      Repo.all(
        from(layer in SceneLayer,
          where: layer.scene_id == ^scene_id and layer.id in ^layer_ids,
          order_by: [asc: layer.id],
          lock: "FOR UPDATE",
          select: layer.id
        )
      )

    if locked_ids == Enum.sort(layer_ids) do
      :ok
    else
      {:error, {:invalid_scene_layer_reorder, layer_ids}}
    end
  end

  defp normalize_reorder_ids(layer_ids) do
    with {:ok, normalized_ids} <- normalize_positive_ids(layer_ids),
         true <- length(normalized_ids) == MapSet.size(MapSet.new(normalized_ids)) do
      {:ok, normalized_ids}
    else
      _error -> {:error, {:invalid_scene_layer_reorder, layer_ids}}
    end
  end

  defp normalize_positive_ids(ids) do
    ids
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, normalized} ->
      case ProjectReferenceIntegrity.normalize_optional_id(id) do
        {:ok, normalized_id} when is_integer(normalized_id) ->
          {:cont, {:ok, [normalized_id | normalized]}}

        _error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end
end
