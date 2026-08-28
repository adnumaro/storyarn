defmodule Storyarn.Flows.AssetReferences do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.ProjectReferenceIntegrity
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Repo

  @spec lock_active_for_restore(pos_integer(), keyword()) :: :ok | {:error, term()}
  def lock_active_for_restore(project_id, owner_ids)
      when is_integer(project_id) and project_id > 0 and is_list(owner_ids) do
    with {:ok, node_ids} <- normalize_owner_ids(owner_ids),
         {:ok, _asset_ids} <-
           ProjectReferenceIntegrity.lock_active_references(
             project_id,
             reference_specs(node_ids)
           ) do
      :ok
    end
  end

  def lock_active_for_restore(_project_id, _owner_ids), do: {:error, :invalid_asset_restore_owners}

  defp normalize_owner_ids(owner_ids) do
    if Keyword.keyword?(owner_ids) and Keyword.keys(owner_ids) -- [:flow_node_ids] == [] do
      ids = owner_ids |> Keyword.get(:flow_node_ids, []) |> List.wrap() |> Enum.uniq()

      if Enum.all?(ids, &(is_integer(&1) and &1 > 0)),
        do: {:ok, ids},
        else: {:error, :invalid_asset_restore_owners}
    else
      {:error, :invalid_asset_restore_owners}
    end
  end

  defp reference_specs([]), do: []

  defp reference_specs(node_ids) do
    audio =
      Repo.all(
        from(node in FlowNode,
          where: node.id in ^node_ids,
          select: {node.id, fragment("?->>'audio_asset_id'", node.data)}
        )
      )

    tracks =
      Repo.all(
        from(track in SequenceTrack,
          where: track.flow_node_id in ^node_ids,
          select: {track.id, track.asset_id}
        )
      )

    layers =
      Repo.all(
        from(layer in SequenceVisualLayer,
          where: layer.flow_node_id in ^node_ids,
          select: {layer.id, layer.asset_id}
        )
      )

    Enum.map(audio, fn {node_id, asset_id} ->
      {:asset, {:flow_node, node_id, :audio_asset_id}, asset_id}
    end) ++
      Enum.map(tracks, fn {track_id, asset_id} ->
        {:asset, {:sequence_track, track_id, :asset_id}, asset_id}
      end) ++
      Enum.map(layers, fn {layer_id, asset_id} ->
        {:asset, {:sequence_visual_layer, layer_id, :asset_id}, asset_id}
      end)
  end
end
