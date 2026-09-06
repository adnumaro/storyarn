defmodule Storyarn.Flows.Editor.Commands.CompositionOwnerDuplicate do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Editor.Commands.CompositionSourceUpdate
  alias Storyarn.Flows.Editor.Commands.ItemCapacity
  alias Storyarn.Flows.Editor.Commands.SequenceCompositionWrite
  alias Storyarn.Flows.Editor.Commands.SequenceCreate
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.References
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @visual_layer_copy_fields [
    :asset_id,
    :layer_key,
    :overridden_fields,
    :removed,
    :kind,
    :label,
    :z_index,
    :slot,
    :x,
    :y,
    :width,
    :height,
    :anchor_x,
    :anchor_y,
    :fit,
    :opacity,
    :visible
  ]
  @track_copy_fields [
    :track_key,
    :is_override,
    :overridden_fields,
    :removed,
    :kind,
    :position,
    :asset_id,
    :start_time,
    :end_time,
    :volume
  ]

  @spec duplicate(Flow.t(), FlowNode.t()) ::
          {:ok, FlowNode.t()} | {:error, term()} | {:error, :limit_reached, map()}
  def duplicate(%Flow{} = flow, %FlowNode{id: source_id}) when is_integer(source_id) do
    fn -> duplicate_in_transaction(flow, source_id) end
    |> Repo.transaction()
    |> normalize_duplicate_result()
    |> broadcast_sequence_result()
  end

  def duplicate(_flow, _node), do: {:error, :composition_owner_not_found}

  defp duplicate_in_transaction(flow, source_id) do
    with {:ok, %{flow: locked_flow, project: project, project_id: project_id}} <-
           References.lock_active_flow_for_write(flow),
         :ok <- ItemCapacity.can_create_item?(project),
         %FlowNode{} = source <- lock_composition_owner_for_duplicate(locked_flow.id, source_id),
         source =
           Repo.preload(source, [
             :sequence_config,
             :sequence_tracks,
             :sequence_visual_layers
           ]),
         {:ok, duplicate} <- insert_composition_duplicate(locked_flow, source, project_id),
         {:ok, duplicate} <- CompositionSourceUpdate.set(duplicate.id, source.composition_source_id),
         :ok <- duplicate_visual_layers(source, duplicate.id, project_id),
         :ok <- duplicate_tracks(source, duplicate.id, project_id) do
      duplicate = Repo.preload(duplicate, :sequence_config, force: true)
      {duplicate, project_id}
    else
      nil -> Repo.rollback(:composition_owner_not_found)
      {:error, :limit_reached, details} -> Repo.rollback({:limit_reached, details})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_composition_owner_for_duplicate(flow_id, source_id) do
    Repo.one(
      from(node in FlowNode,
        where:
          node.id == ^source_id and node.flow_id == ^flow_id and
            node.type in ["sequence", "dialogue"] and is_nil(node.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp insert_composition_duplicate(flow, %FlowNode{type: "dialogue"} = source, _project_id) do
    NodeCrud.create_node_without_dashboard_broadcast(flow, %{
      "type" => "dialogue",
      "position_x" => source.position_x + 50.0,
      "position_y" => source.position_y + 50.0,
      "parent_id" => source.parent_id,
      "composition_source_id" => nil,
      "data" => NodeTypes.duplicate_data("dialogue", source.data)
    })
  end

  defp insert_composition_duplicate(
         flow,
         %FlowNode{type: "sequence", sequence_config: %SequenceConfig{} = config} = source,
         project_id
       ) do
    attrs = %{
      "name" => config.name,
      "position_x" => source.position_x + 50.0,
      "position_y" => source.position_y + 50.0,
      "parent_id" => source.parent_id,
      "width" => config.width,
      "height" => config.height
    }

    case SequenceCreate.insert_in_transaction(flow.id, attrs) do
      {duplicate, ^project_id} -> {:ok, duplicate}
      {_duplicate, _other_project_id} -> {:error, :flow_scope_mismatch}
    end
  end

  defp insert_composition_duplicate(_flow, _source, _project_id), do: {:error, :invalid_sequence_config}

  defp duplicate_visual_layers(source, duplicate_id, project_id) do
    source.sequence_visual_layers
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while(:ok, fn layer, :ok ->
      with {:ok, asset_id} <-
             SequenceCompositionWrite.lock_project_asset(
               project_id,
               :sequence_visual_asset_id,
               layer.asset_id,
               "image/%"
             ),
           attrs =
             layer
             |> Map.from_struct()
             |> Map.take(@visual_layer_copy_fields)
             |> Map.put(:flow_node_id, duplicate_id)
             |> Map.put(:asset_id, asset_id),
           {:ok, _copy} <-
             %SequenceVisualLayer{}
             |> SequenceVisualLayer.override_changeset(attrs)
             |> Repo.insert() do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp duplicate_tracks(source, duplicate_id, project_id) do
    source.sequence_tracks
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while(:ok, fn track, :ok ->
      with {:ok, asset_id} <-
             SequenceCompositionWrite.lock_project_asset(
               project_id,
               :sequence_track_asset_id,
               track.asset_id,
               "audio/%"
             ),
           attrs =
             track
             |> Map.from_struct()
             |> Map.take(@track_copy_fields)
             |> Map.put(:flow_node_id, duplicate_id)
             |> Map.put(:asset_id, asset_id),
           {:ok, _copy} <-
             %SequenceTrack{}
             |> SequenceTrack.override_changeset(attrs)
             |> Repo.insert() do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_duplicate_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_duplicate_result(result), do: result

  defp broadcast_sequence_result({:ok, {sequence, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, sequence}
  end

  defp broadcast_sequence_result(result), do: result
end
