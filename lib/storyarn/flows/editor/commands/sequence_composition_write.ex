defmodule Storyarn.Flows.Editor.Commands.SequenceCompositionWrite do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Editor.Projections.AssetRecord
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.References
  alias Storyarn.Flows.SequenceCompositionIntegrity
  alias Storyarn.Repo

  @doc false
  def normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  @doc false
  def lock_owner(owner_id) do
    with {:ok, %{node: node} = context} <-
           References.lock_active_node_for_write(owner_id),
         :ok <- ensure_composition_owner(node) do
      {:ok, context}
    end
  end

  @doc false
  def lock_project_asset(project_id, context, asset_id, content_type_pattern) do
    with {:ok, [normalized_asset_id]} <-
           References.lock_active_references(project_id, [
             {:asset, context, asset_id}
           ]),
         :ok <-
           validate_asset_content_type(
             project_id,
             context,
             normalized_asset_id,
             content_type_pattern
           ) do
      {:ok, normalized_asset_id}
    end
  end

  @doc false
  def validate_dependents(flow_id, owner_id) do
    result =
      flow_id
      |> composition_nodes_including_deleted()
      |> Map.values()
      |> Enum.map(&composition_integrity_node/1)
      |> SequenceCompositionIntegrity.validate_affected(owner_id)

    case result do
      :ok -> :ok
      {:error, _reason} -> {:error, :composition_dependency_conflict}
    end
  end

  @doc false
  def normalize_override_attrs(attrs, allowed_fields) do
    attrs = normalize_keys(attrs)
    fields = Map.keys(attrs)
    invalid = fields -- allowed_fields

    cond do
      invalid != [] -> {:error, {:invalid_override_fields, Enum.sort(invalid)}}
      fields == [] -> {:error, :empty_override}
      true -> {:ok, attrs, Enum.sort(fields)}
    end
  end

  @doc false
  def normalize_override_fields(fields, allowed_fields) do
    if Enum.all?(fields, &(is_atom(&1) or is_binary(&1))) do
      normalized_fields = Enum.map(fields, &to_string/1)
      unique_fields = Enum.uniq(normalized_fields)
      invalid = unique_fields -- allowed_fields

      cond do
        length(unique_fields) != length(normalized_fields) ->
          {:error, {:invalid_override_fields, Enum.sort(normalized_fields)}}

        invalid != [] ->
          {:error, {:invalid_override_fields, Enum.sort(invalid)}}

        true ->
          {:ok, Enum.sort(normalized_fields)}
      end
    else
      {:error, {:invalid_override_fields, fields}}
    end
  end

  @doc false
  def relational_attrs(item, fields), do: Map.new(fields, &{&1, map_value(item, property_atom(&1))})

  @doc false
  def map_value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp ensure_composition_owner(%FlowNode{type: type, deleted_at: nil}) when type in ["sequence", "dialogue"], do: :ok

  defp ensure_composition_owner(_node), do: {:error, :composition_owner_not_found}

  defp validate_asset_content_type(_project_id, _context, nil, _content_type_pattern), do: :ok

  defp validate_asset_content_type(project_id, context, asset_id, content_type_pattern) do
    if Repo.exists?(
         from(asset in AssetRecord,
           where:
             asset.id == ^asset_id and asset.project_id == ^project_id and
               is_nil(asset.deleted_at) and
               like(asset.content_type, ^content_type_pattern)
         )
       ) do
      :ok
    else
      {:error, {:invalid_asset_content_type, context, asset_id}}
    end
  end

  defp composition_nodes_including_deleted(flow_id) do
    from(node in FlowNode,
      where: node.flow_id == ^flow_id and node.type in ["sequence", "dialogue"],
      preload: [sequence_tracks: [:asset], sequence_visual_layers: [:asset]]
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp composition_integrity_node(node) do
    %{
      "original_id" => node.id,
      "type" => node.type,
      "deleted_at" => node.deleted_at,
      "composition_source_original_id" => node.composition_source_id,
      "sequence_config" => composition_integrity_config(node),
      "sequence_tracks" => Enum.map(node.sequence_tracks, &composition_integrity_track/1),
      "sequence_visual_layers" => Enum.map(node.sequence_visual_layers, &composition_integrity_visual_layer/1)
    }
  end

  defp composition_integrity_config(%FlowNode{type: "sequence"}), do: %{}
  defp composition_integrity_config(_node), do: nil

  defp composition_integrity_track(track) do
    %{
      "track_key" => track.track_key,
      "kind" => track.kind,
      "is_override" => track.is_override,
      "overridden_fields" => track.overridden_fields,
      "removed" => track.removed
    }
  end

  defp composition_integrity_visual_layer(layer) do
    %{
      "layer_key" => layer.layer_key,
      "overridden_fields" => layer.overridden_fields,
      "removed" => layer.removed
    }
  end

  defp property_atom("asset_id"), do: :asset_id
  defp property_atom("kind"), do: :kind
  defp property_atom("label"), do: :label
  defp property_atom("z_index"), do: :z_index
  defp property_atom("slot"), do: :slot
  defp property_atom("x"), do: :x
  defp property_atom("y"), do: :y
  defp property_atom("width"), do: :width
  defp property_atom("height"), do: :height
  defp property_atom("anchor_x"), do: :anchor_x
  defp property_atom("anchor_y"), do: :anchor_y
  defp property_atom("fit"), do: :fit
  defp property_atom("opacity"), do: :opacity
  defp property_atom("visible"), do: :visible
  defp property_atom("position"), do: :position
  defp property_atom("start_time"), do: :start_time
  defp property_atom("end_time"), do: :end_time
  defp property_atom("volume"), do: :volume
end
