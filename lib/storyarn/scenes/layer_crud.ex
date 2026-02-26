defmodule Storyarn.Scenes.LayerCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.{PositionUtils, SceneAnnotation, SceneLayer, ScenePin, SceneZone}
  alias Storyarn.Shared.TreeOperations

  @doc """
  Lists all layers for a map, ordered by position.
  """
  def list_layers(scene_id) do
    from(l in SceneLayer,
      where: l.scene_id == ^scene_id,
      order_by: [asc: l.position]
    )
    |> Repo.all()
  end

  def get_layer(scene_id, layer_id) do
    from(l in SceneLayer,
      where: l.scene_id == ^scene_id and l.id == ^layer_id
    )
    |> Repo.one()
  end

  def get_layer!(scene_id, layer_id) do
    from(l in SceneLayer,
      where: l.scene_id == ^scene_id and l.id == ^layer_id
    )
    |> Repo.one!()
  end

  def create_layer(scene_id, attrs) do
    # Auto-assign position
    position = PositionUtils.next_position(SceneLayer, scene_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    %SceneLayer{scene_id: scene_id}
    |> SceneLayer.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_layer(%SceneLayer{} = layer, attrs) do
    layer
    |> SceneLayer.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Toggles the visibility of a layer.
  """
  def toggle_layer_visibility(%SceneLayer{} = layer) do
    layer
    |> Ecto.Changeset.change(visible: !layer.visible)
    |> Repo.update()
  end

  @doc """
  Deletes a layer. Prevents deleting the last layer in a map.
  When deleted, zones and pins on this layer have their layer_id set to nil (via FK nilify_all).
  """
  def delete_layer(%SceneLayer{} = layer) do
    Repo.transaction(fn ->
      # Lock all layers for this map, then count in Elixir to prevent race condition
      # (FOR UPDATE cannot be combined with aggregate functions in PostgreSQL)
      layer_count =
        from(l in SceneLayer,
          where: l.scene_id == ^layer.scene_id,
          lock: "FOR UPDATE",
          select: l.id
        )
        |> Repo.all()
        |> length()

      if layer_count <= 1 do
        Repo.rollback(:cannot_delete_last_layer)
      else
        do_delete_layer(layer)
      end
    end)
  end

  defp do_delete_layer(layer) do
    from(z in SceneZone, where: z.layer_id == ^layer.id)
    |> Repo.update_all(set: [layer_id: nil])

    from(p in ScenePin, where: p.layer_id == ^layer.id)
    |> Repo.update_all(set: [layer_id: nil])

    from(a in SceneAnnotation, where: a.layer_id == ^layer.id)
    |> Repo.update_all(set: [layer_id: nil])

    case Repo.delete(layer) do
      {:ok, deleted} -> deleted
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Reorders layers by updating positions in a transaction.
  """
  def reorder_layers(scene_id, layer_ids) when is_list(layer_ids) do
    pairs = Enum.with_index(layer_ids)

    Repo.transaction(fn ->
      TreeOperations.batch_set_positions("scene_layers", pairs, scope: {"scene_id", scene_id})

      list_layers(scene_id)
    end)
  end

  def change_layer(%SceneLayer{} = layer, attrs \\ %{}) do
    SceneLayer.update_changeset(layer, attrs)
  end
end
