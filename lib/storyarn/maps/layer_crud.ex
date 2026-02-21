defmodule Storyarn.Maps.LayerCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{MapAnnotation, MapLayer, MapPin, MapZone, PositionUtils}
  alias Storyarn.Repo

  @doc """
  Lists all layers for a map, ordered by position.
  """
  def list_layers(map_id) do
    from(l in MapLayer,
      where: l.map_id == ^map_id,
      order_by: [asc: l.position]
    )
    |> Repo.all()
  end

  def get_layer(map_id, layer_id) do
    from(l in MapLayer,
      where: l.map_id == ^map_id and l.id == ^layer_id
    )
    |> Repo.one()
  end

  def get_layer!(map_id, layer_id) do
    from(l in MapLayer,
      where: l.map_id == ^map_id and l.id == ^layer_id
    )
    |> Repo.one!()
  end

  def create_layer(map_id, attrs) do
    # Auto-assign position
    position = PositionUtils.next_position(MapLayer, map_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    %MapLayer{map_id: map_id}
    |> MapLayer.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_layer(%MapLayer{} = layer, attrs) do
    layer
    |> MapLayer.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Toggles the visibility of a layer.
  """
  def toggle_layer_visibility(%MapLayer{} = layer) do
    layer
    |> Ecto.Changeset.change(visible: !layer.visible)
    |> Repo.update()
  end

  @doc """
  Deletes a layer. Prevents deleting the last layer in a map.
  When deleted, zones and pins on this layer have their layer_id set to nil (via FK nilify_all).
  """
  def delete_layer(%MapLayer{} = layer) do
    Repo.transaction(fn ->
      # Lock all layers for this map, then count in Elixir to prevent race condition
      # (FOR UPDATE cannot be combined with aggregate functions in PostgreSQL)
      layer_count =
        from(l in MapLayer, where: l.map_id == ^layer.map_id, lock: "FOR UPDATE", select: l.id)
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
    from(z in MapZone, where: z.layer_id == ^layer.id)
    |> Repo.update_all(set: [layer_id: nil])

    from(p in MapPin, where: p.layer_id == ^layer.id)
    |> Repo.update_all(set: [layer_id: nil])

    from(a in MapAnnotation, where: a.layer_id == ^layer.id)
    |> Repo.update_all(set: [layer_id: nil])

    case Repo.delete(layer) do
      {:ok, deleted} -> deleted
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Reorders layers by updating positions in a transaction.
  """
  def reorder_layers(map_id, layer_ids) when is_list(layer_ids) do
    Repo.transaction(fn ->
      layer_ids
      |> Enum.with_index()
      |> Enum.each(fn {layer_id, index} ->
        from(l in MapLayer, where: l.id == ^layer_id and l.map_id == ^map_id)
        |> Repo.update_all(set: [position: index])
      end)

      list_layers(map_id)
    end)
  end

  def change_layer(%MapLayer{} = layer, attrs \\ %{}) do
    MapLayer.update_changeset(layer, attrs)
  end
end
