defmodule Storyarn.Flows.Editor.Queries.Sequences do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Repo

  def list(flow_id, deleted? \\ false) do
    deleted_filter =
      if deleted?, do: dynamic([node], not is_nil(node.deleted_at)), else: dynamic([node], is_nil(node.deleted_at))

    order = if deleted?, do: [desc: :deleted_at], else: [asc: :inserted_at]

    Repo.all(
      from(node in FlowNode,
        where: node.flow_id == ^flow_id and node.type == "sequence",
        where: ^deleted_filter,
        order_by: ^order,
        preload: [:sequence_config]
      )
    )
  end

  def get(flow_id, id, include_deleted? \\ false) do
    query =
      from(node in FlowNode,
        where: node.id == ^id and node.flow_id == ^flow_id and node.type == "sequence",
        preload: [:sequence_config]
      )

    query = if include_deleted?, do: query, else: where(query, [node], is_nil(node.deleted_at))
    Repo.one(query)
  end

  def get!(flow_id, id) do
    Repo.one!(
      from(node in FlowNode,
        where: node.id == ^id and node.flow_id == ^flow_id and node.type == "sequence",
        preload: [:sequence_config]
      )
    )
  end

  def get_config(sequence_id) do
    Repo.one(
      from(config in SequenceConfig,
        join: node in FlowNode,
        on: node.id == config.flow_node_id,
        where:
          config.flow_node_id == ^sequence_id and node.type == "sequence" and
            is_nil(node.deleted_at),
        select: config
      )
    )
  end

  def list_visual_layers(sequence_id) do
    Repo.all(
      from(layer in SequenceVisualLayer,
        where: layer.flow_node_id == ^sequence_id,
        order_by: [asc: layer.z_index, asc: layer.id],
        preload: [:asset]
      )
    )
  end

  def get_visual_layer(sequence_id, id) do
    Repo.one(
      from(layer in SequenceVisualLayer,
        where: layer.flow_node_id == ^sequence_id and layer.id == ^id,
        preload: [:asset]
      )
    )
  end

  def list_tracks(sequence_id) do
    Repo.all(
      from(track in SequenceTrack,
        where: track.flow_node_id == ^sequence_id,
        order_by: [asc: track.kind, asc: track.position]
      )
    )
  end

  def get_track(sequence_id, kind) do
    Repo.one(
      from(track in SequenceTrack,
        where: track.flow_node_id == ^sequence_id and track.kind == ^kind
      )
    )
  end
end
