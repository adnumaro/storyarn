defmodule Storyarn.Flows.Editor.Commands.SequenceVisualLayers do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Editor.Commands.SequenceCompositionWrite
  alias Storyarn.Flows.Editor.Queries.SequenceComposition
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Repo

  @doc "Creates a local visual-layer definition above existing layers unless an explicit z-index is supplied."
  @spec create_sequence_visual_layer(integer(), map()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, Ecto.Changeset.t()}
  def create_sequence_visual_layer(sequence_id, attrs) when is_integer(sequence_id) and is_map(attrs) do
    attrs =
      attrs
      |> SequenceCompositionWrite.normalize_keys()
      |> Map.drop(~w(flow_node_id layer_key overridden_fields removed))

    kind = Map.get(attrs, "kind", "prop")
    explicit_z_index? = Map.has_key?(attrs, "z_index")
    slot = normalize_visual_slot(kind, Map.get(attrs, "slot", default_slot_for_visual_kind(kind)))

    attrs =
      kind
      |> visual_layer_defaults(slot)
      |> Map.merge(attrs)
      |> Map.put("flow_node_id", sequence_id)
      |> Map.put("kind", kind)
      |> Map.put("slot", slot)

    Repo.transaction(fn ->
      with {:ok, %{project_id: project_id}} <- SequenceCompositionWrite.lock_owner(sequence_id),
           attrs = default_insertion_order(attrs, sequence_id, explicit_z_index?),
           changeset = SequenceVisualLayer.create_changeset(%SequenceVisualLayer{}, attrs),
           asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
           {:ok, asset_id} <-
             SequenceCompositionWrite.lock_project_asset(
               project_id,
               :sequence_visual_asset_id,
               asset_id,
               "image/%"
             ),
           {:ok, layer} <-
             changeset
             |> Ecto.Changeset.put_change(:asset_id, asset_id)
             |> Repo.insert() do
        layer
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp default_insertion_order(attrs, _owner_id, true), do: attrs

  defp default_insertion_order(attrs, owner_id, false) do
    highest_z_index =
      Repo.one(
        from(layer in SequenceVisualLayer,
          where: layer.flow_node_id == ^owner_id,
          select: max(layer.z_index)
        )
      )

    # A new logical key follows manually ordered keys, and local definitions
    # follow inherited definitions. Only its place among other local keys needs
    # a new z-index; preserving the owner's order also preserves live inheritance.
    if is_integer(highest_z_index),
      do: Map.put(attrs, "z_index", max(attrs["z_index"], highest_z_index + 1)),
      else: attrs
  end

  @doc "Updates a local visual-layer row."
  @spec update_sequence_visual_layer(SequenceVisualLayer.t(), map()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, Ecto.Changeset.t()}
  def update_sequence_visual_layer(%SequenceVisualLayer{} = layer, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, locked_layer, %{project_id: project_id}} <- lock_visual_layer_for_write(layer),
           attrs =
             normalize_visual_layer_update_attrs(
               locked_layer,
               SequenceCompositionWrite.normalize_keys(attrs)
             ),
           changeset = SequenceVisualLayer.update_changeset(locked_layer, attrs),
           asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
           {:ok, asset_id} <-
             SequenceCompositionWrite.lock_project_asset(
               project_id,
               :sequence_visual_asset_id,
               asset_id,
               "image/%"
             ),
           {:ok, updated_layer} <-
             changeset
             |> Ecto.Changeset.put_change(:asset_id, asset_id)
             |> Repo.update() do
        updated_layer
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Deletes a local visual-layer row."
  @spec delete_sequence_visual_layer(SequenceVisualLayer.t()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, atom() | Ecto.Changeset.t()}
  def delete_sequence_visual_layer(%SequenceVisualLayer{} = layer) do
    Repo.transaction(fn ->
      with {:ok, locked_layer, context} <- lock_visual_layer_for_write(layer),
           {:ok, deleted_layer} <- Repo.delete(locked_layer),
           :ok <-
             SequenceCompositionWrite.validate_dependents(
               context.flow.id,
               locked_layer.flow_node_id
             ) do
        deleted_layer
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Creates or updates the local property patch for an inherited visual layer."
  def override_sequence_visual_layer(owner_id, layer_key, attrs)
      when is_integer(owner_id) and is_binary(layer_key) and is_map(attrs) do
    with {:ok, attrs, fields} <-
           SequenceCompositionWrite.normalize_override_attrs(
             attrs,
             SequenceVisualLayer.property_fields()
           ) do
      Repo.transaction(fn ->
        do_override_sequence_visual_layer(owner_id, layer_key, attrs, fields)
      end)
    end
  end

  defp do_override_sequence_visual_layer(owner_id, layer_key, attrs, fields) do
    with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
         {:ok, inherited} <-
           SequenceComposition.inherited_visual_layer(context.flow.id, context.node, layer_key),
         local = lock_visual_layer_by_key(owner_id, layer_key),
         attrs = normalize_visual_layer_override_attrs(attrs, local, inherited.item),
         changeset =
           visual_layer_override_changeset(
             local,
             inherited.item,
             owner_id,
             layer_key,
             attrs,
             fields
           ),
         asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
         {:ok, asset_id} <-
           SequenceCompositionWrite.lock_project_asset(
             context.project_id,
             :sequence_visual_asset_id,
             asset_id,
             "image/%"
           ),
         {:ok, persisted} <- persist_visual_layer(changeset, asset_id, local) do
      persisted
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Returns selected local visual-layer properties to inheritance."
  def revert_sequence_visual_layer_fields(owner_id, layer_key, fields)
      when is_integer(owner_id) and is_binary(layer_key) and is_list(fields) do
    with {:ok, fields} <-
           SequenceCompositionWrite.normalize_override_fields(
             fields,
             SequenceVisualLayer.property_fields()
           ) do
      Repo.transaction(fn ->
        do_revert_sequence_visual_layer_fields(owner_id, layer_key, fields)
      end)
    end
  end

  defp do_revert_sequence_visual_layer_fields(owner_id, layer_key, fields) do
    with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
         {:ok, _inherited} <-
           SequenceComposition.inherited_visual_layer(context.flow.id, context.node, layer_key),
         %SequenceVisualLayer{} = local <- lock_visual_layer_by_key(owner_id, layer_key),
         {:ok, result} <- revert_or_delete_visual_layer(local, fields) do
      result
    else
      nil -> :inherited
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Removes a local layer definition or tombstones an inherited layer."
  def remove_sequence_visual_layer(owner_id, layer_key) when is_integer(owner_id) and is_binary(layer_key) do
    Repo.transaction(fn ->
      with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
           local = lock_visual_layer_by_key(owner_id, layer_key),
           {:ok, removed} <-
             remove_visual_layer(context.flow.id, context.node, local, owner_id, layer_key),
           :ok <- SequenceCompositionWrite.validate_dependents(context.flow.id, owner_id) do
        removed
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Restores a local tombstone or materializes an inherited tombstoned layer."
  def restore_sequence_visual_layer(owner_id, layer_key) when is_integer(owner_id) and is_binary(layer_key) do
    Repo.transaction(fn ->
      with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
           local = lock_visual_layer_by_key(owner_id, layer_key),
           {:ok, restored} <- restore_visual_layer(context, local, owner_id, layer_key) do
        restored
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp default_slot_for_visual_kind("backdrop"), do: "full"
  defp default_slot_for_visual_kind("overlay"), do: "full"
  defp default_slot_for_visual_kind("character"), do: "bottom-center"
  defp default_slot_for_visual_kind(_), do: "middle-center"

  defp normalize_visual_slot(kind, "left"), do: normalize_visual_slot(kind, "bottom-left")
  defp normalize_visual_slot(kind, "right"), do: normalize_visual_slot(kind, "bottom-right")
  defp normalize_visual_slot("character", "center"), do: "bottom-center"
  defp normalize_visual_slot(_kind, "center"), do: "middle-center"

  defp normalize_visual_slot(_kind, slot)
       when slot in [
              "full",
              "custom",
              "top-left",
              "top-center",
              "top-right",
              "middle-left",
              "middle-center",
              "middle-right",
              "bottom-left",
              "bottom-center",
              "bottom-right"
            ], do: slot

  defp normalize_visual_slot(kind, _slot), do: default_slot_for_visual_kind(kind)

  defp normalize_visual_layer_update_attrs(%SequenceVisualLayer{} = layer, attrs) do
    case Map.fetch(attrs, "slot") do
      {:ok, slot} ->
        kind = Map.get(attrs, "kind", layer.kind)
        Map.put(attrs, "slot", normalize_visual_slot(kind, slot))

      :error ->
        attrs
    end
  end

  defp normalize_visual_layer_override_attrs(attrs, local, inherited) do
    case Map.fetch(attrs, "slot") do
      {:ok, slot} ->
        kind = visual_layer_override_kind(attrs, local, inherited)
        Map.put(attrs, "slot", normalize_visual_slot(kind, slot))

      :error ->
        attrs
    end
  end

  defp visual_layer_override_kind(attrs, local, inherited) do
    case Map.fetch(attrs, "kind") do
      {:ok, kind} -> kind
      :error -> visual_layer_override_kind(local, inherited)
    end
  end

  defp visual_layer_override_kind(%SequenceVisualLayer{kind: kind, overridden_fields: overridden_fields}, inherited) do
    if "kind" in List.wrap(overridden_fields),
      do: kind,
      else: SequenceCompositionWrite.map_value(inherited, :kind)
  end

  defp visual_layer_override_kind(nil, inherited), do: SequenceCompositionWrite.map_value(inherited, :kind)

  defp visual_layer_defaults("backdrop", _slot) do
    %{
      "slot" => "full",
      "x" => 0.0,
      "y" => 0.0,
      "width" => 1.0,
      "height" => 1.0,
      "anchor_x" => 0.0,
      "anchor_y" => 0.0,
      "fit" => "cover",
      "z_index" => 0,
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp visual_layer_defaults(kind, "full") do
    %{
      "slot" => "full",
      "x" => 0.0,
      "y" => 0.0,
      "width" => 1.0,
      "height" => 1.0,
      "anchor_x" => 0.0,
      "anchor_y" => 0.0,
      "fit" => if(kind in ["backdrop", "overlay"], do: "cover", else: "contain"),
      "z_index" => visual_layer_z_index(kind),
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp visual_layer_defaults("character", slot) do
    {row, col} = position_parts(slot, "bottom-center")
    x = column_x(col, :character)
    y = row_y(row, :character)
    width = if col == "center", do: 0.42, else: 0.38

    %{
      "x" => x,
      "y" => y,
      "width" => width,
      "height" => 0.9,
      "anchor_x" => 0.5,
      "anchor_y" => row_anchor_y(row),
      "fit" => "contain",
      "z_index" => 100,
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp visual_layer_defaults(kind, slot) do
    {row, col} = position_parts(slot, "middle-center")

    %{
      "x" => column_x(col, :safe_center),
      "y" => row_y(row, :safe_center),
      "width" => 0.25,
      "height" => 0.25,
      "anchor_x" => 0.5,
      "anchor_y" => 0.5,
      "fit" => "contain",
      "z_index" => visual_layer_z_index(kind),
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp position_parts(slot, fallback) do
    slot =
      if slot in [
           "top-left",
           "top-center",
           "top-right",
           "middle-left",
           "middle-center",
           "middle-right",
           "bottom-left",
           "bottom-center",
           "bottom-right"
         ] do
        slot
      else
        fallback
      end

    [row, col] = String.split(slot, "-", parts: 2)
    {row, col}
  end

  defp column_x("left", :character), do: 0.25
  defp column_x("right", :character), do: 0.75
  defp column_x("center", :character), do: 0.5
  defp column_x("left", :safe_center), do: 0.2
  defp column_x("right", :safe_center), do: 0.8
  defp column_x("center", :safe_center), do: 0.5

  defp row_y("top", :character), do: 0.0
  defp row_y("bottom", :character), do: 1.0
  defp row_y("middle", :character), do: 0.5
  defp row_y("top", :safe_center), do: 0.2
  defp row_y("bottom", :safe_center), do: 0.8
  defp row_y("middle", :safe_center), do: 0.5

  defp row_anchor_y("top"), do: 0.0
  defp row_anchor_y("bottom"), do: 1.0
  defp row_anchor_y("middle"), do: 0.5

  defp visual_layer_z_index("backdrop"), do: 0
  defp visual_layer_z_index("character"), do: 100
  defp visual_layer_z_index("overlay"), do: 300
  defp visual_layer_z_index(_kind), do: 200

  defp lock_visual_layer_for_write(%SequenceVisualLayer{id: layer_id, flow_node_id: sequence_id})
       when is_integer(layer_id) and is_integer(sequence_id) do
    with {:ok, context} <- SequenceCompositionWrite.lock_owner(sequence_id),
         %SequenceVisualLayer{} = layer <-
           Repo.one(
             from(layer in SequenceVisualLayer,
               where:
                 layer.id == ^layer_id and
                   layer.flow_node_id == ^sequence_id,
               lock: "FOR UPDATE"
             )
           ) do
      {:ok, layer, context}
    else
      nil -> {:error, :sequence_visual_layer_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp lock_visual_layer_for_write(_layer), do: {:error, :sequence_visual_layer_not_found}

  defp visual_layer_override_changeset(nil, inherited, owner_id, layer_key, attrs, fields) do
    inherited
    |> SequenceCompositionWrite.relational_attrs(SequenceVisualLayer.property_fields())
    |> Map.merge(attrs)
    |> Map.merge(%{
      "flow_node_id" => owner_id,
      "layer_key" => layer_key,
      "overridden_fields" => fields,
      "removed" => false
    })
    |> then(&SequenceVisualLayer.override_changeset(%SequenceVisualLayer{}, &1))
  end

  defp visual_layer_override_changeset(%SequenceVisualLayer{} = local, _inherited, _owner_id, _layer_key, attrs, _fields) do
    local
    |> SequenceVisualLayer.update_changeset(attrs)
    |> Ecto.Changeset.put_change(:removed, false)
  end

  defp persist_visual_layer(changeset, asset_id, nil) do
    changeset
    |> Ecto.Changeset.put_change(:asset_id, asset_id)
    |> Repo.insert()
  end

  defp persist_visual_layer(changeset, asset_id, %SequenceVisualLayer{}) do
    changeset
    |> Ecto.Changeset.put_change(:asset_id, asset_id)
    |> Repo.update()
  end

  defp lock_visual_layer_by_key(owner_id, layer_key) do
    Repo.one(
      from(layer in SequenceVisualLayer,
        where: layer.flow_node_id == ^owner_id and layer.layer_key == ^layer_key,
        lock: "FOR UPDATE"
      )
    )
  end

  defp revert_or_delete_visual_layer(local, fields) do
    changeset = SequenceVisualLayer.revert_fields_changeset(local, fields)

    if Ecto.Changeset.get_field(changeset, :overridden_fields) == [] and
         not Ecto.Changeset.get_field(changeset, :removed) do
      case Repo.delete(local) do
        {:ok, _deleted} -> {:ok, :inherited}
        {:error, reason} -> {:error, reason}
      end
    else
      Repo.update(changeset)
    end
  end

  defp persist_visual_layer_tombstone(nil, effective, owner_id, layer_key) do
    effective
    |> SequenceCompositionWrite.relational_attrs(SequenceVisualLayer.property_fields())
    |> Map.merge(%{
      "flow_node_id" => owner_id,
      "layer_key" => layer_key,
      "overridden_fields" => [],
      "removed" => true
    })
    |> then(&SequenceVisualLayer.override_changeset(%SequenceVisualLayer{}, &1))
    |> Repo.insert()
  end

  defp remove_visual_layer(_flow_id, _owner, %SequenceVisualLayer{removed: true} = local, _owner_id, _layer_key),
    do: {:ok, local}

  defp remove_visual_layer(flow_id, owner, nil, owner_id, layer_key) do
    with {:ok, inherited} <- SequenceComposition.inherited_visual_layer(flow_id, owner, layer_key) do
      persist_visual_layer_tombstone(nil, inherited.item, owner_id, layer_key)
    end
  end

  defp remove_visual_layer(flow_id, owner, %SequenceVisualLayer{} = local, _owner_id, layer_key) do
    case SequenceComposition.inherited_visual_layer(flow_id, owner, layer_key) do
      {:ok, _inherited} ->
        local |> SequenceVisualLayer.removal_changeset(true) |> Repo.update()

      {:error, :inherited_layer_not_found} ->
        Repo.delete(local)

      {:error, _reason} = error ->
        error
    end
  end

  defp restore_visual_layer(_context, %SequenceVisualLayer{removed: false}, _owner_id, _layer_key),
    do: {:error, :sequence_visual_layer_not_removed}

  defp restore_visual_layer(context, %SequenceVisualLayer{} = local, _owner_id, layer_key) do
    case SequenceComposition.inherited_visual_layer(context.flow.id, context.node, layer_key) do
      {:ok, _inherited} -> restore_visual_layer_row(local)
      {:error, :inherited_layer_not_found} -> clear_orphan_visual_tombstone(local)
      {:error, _reason} = error -> error
    end
  end

  defp restore_visual_layer(context, nil, owner_id, layer_key) do
    fields = SequenceVisualLayer.property_fields()

    with {:ok, inherited} <-
           SequenceComposition.inherited_removed_visual_layer(
             context.flow.id,
             context.node,
             layer_key
           ),
         changeset =
           visual_layer_override_changeset(
             nil,
             inherited.item,
             owner_id,
             layer_key,
             %{},
             fields
           ),
         asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
         {:ok, asset_id} <-
           SequenceCompositionWrite.lock_project_asset(
             context.project_id,
             :sequence_visual_asset_id,
             asset_id,
             "image/%"
           ) do
      persist_visual_layer(changeset, asset_id, nil)
    end
  end

  defp restore_visual_layer_row(%SequenceVisualLayer{overridden_fields: []} = local) do
    case Repo.delete(local) do
      {:ok, _deleted} -> {:ok, :inherited}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_visual_layer_row(local), do: local |> SequenceVisualLayer.removal_changeset(false) |> Repo.update()

  defp clear_orphan_visual_tombstone(local) do
    case Repo.delete(local) do
      {:ok, _deleted} -> {:ok, :cleared}
      {:error, reason} -> {:error, reason}
    end
  end
end
