defmodule Storyarn.FlowsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  flows via the `Storyarn.Flows` context.
  """

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.ProjectsFixtures
  alias Storyarn.Repo

  @sequence_track_fields [:position, :asset_id, :start_time, :end_time, :volume]
  @sequence_visual_layer_fields [
    :asset_id,
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

  def unique_flow_name, do: "Flow #{System.unique_integer([:positive])}"

  def valid_flow_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_flow_name(),
      description: "A test flow"
    })
  end

  @doc """
  Creates a flow.
  """
  def flow_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, flow} =
      attrs
      |> valid_flow_attributes()
      |> then(&Flows.create_flow(project, &1))

    flow
  end

  @doc """
  Inserts a Flow record without the domain creation side effects.

  Use only when a test deliberately needs an incomplete or corrupt persistence
  fixture, such as a Flow with no entry node. Project import/reconstitution has
  its own writer and must not be reached through the Flow facade.
  """
  def raw_flow_fixture(project, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        name: "Raw Flow #{unique}",
        shortcut: "raw-flow-#{unique}"
      })

    %Flow{project_id: project.id}
    |> Flow.create_changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a node within a flow.
  """
  def node_fixture(flow, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        type: "dialogue",
        position_x: 100.0,
        position_y: 100.0,
        data: %{"speaker" => "Character", "text" => "Hello!"}
      })

    {:ok, node} = Flows.create_node(flow, attrs)
    node
  end

  @doc """
  Inserts a Flow node without reference-integrity or domain side effects.

  This is intentionally test-only and should be reserved for malformed legacy
  values or other persistence states that the regular Flow writer rejects.
  """
  def raw_node_fixture(flow, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        type: "dialogue",
        position_x: 100.0,
        position_y: 100.0,
        data: %{"speaker" => "Character", "text" => "Hello!"}
      })

    type = MapAccess.get_flexible(attrs, :type)
    data = MapAccess.get_flexible(attrs, :data)

    %FlowNode{flow_id: flow.id}
    |> FlowNode.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:word_count, Flows.node_word_count(type, data))
    |> Repo.insert!()
  end

  @doc "Inserts a test-only persisted patch or tombstone for an inherited audio track."
  def raw_sequence_track_override_fixture(owner, source, attrs \\ %{}, options \\ []) do
    overridden_fields =
      Keyword.get(options, :overridden_fields, overridden_field_names(attrs, @sequence_track_fields))

    source
    |> Map.from_struct()
    |> Map.take(@sequence_track_fields)
    |> Map.merge(normalize_fixture_attrs(attrs, @sequence_track_fields))
    |> Map.merge(%{
      flow_node_id: owner.id,
      track_key: source.track_key,
      kind: source.kind,
      is_override: true,
      overridden_fields: overridden_fields,
      removed: Keyword.get(options, :removed, false)
    })
    |> then(&SequenceTrack.override_changeset(%SequenceTrack{}, &1))
    |> Repo.insert!()
  end

  @doc "Inserts a test-only persisted patch or tombstone for an inherited visual layer."
  def raw_sequence_visual_override_fixture(owner, source, attrs \\ %{}, options \\ []) do
    overridden_fields =
      Keyword.get(
        options,
        :overridden_fields,
        overridden_field_names(attrs, @sequence_visual_layer_fields)
      )

    source
    |> Map.from_struct()
    |> Map.take(@sequence_visual_layer_fields)
    |> Map.merge(normalize_fixture_attrs(attrs, @sequence_visual_layer_fields))
    |> Map.merge(%{
      flow_node_id: owner.id,
      layer_key: source.layer_key,
      overridden_fields: overridden_fields,
      removed: Keyword.get(options, :removed, false)
    })
    |> then(&SequenceVisualLayer.override_changeset(%SequenceVisualLayer{}, &1))
    |> Repo.insert!()
  end

  @doc """
  Creates a connection between two nodes.
  """
  def connection_fixture(flow, source_node, target_node, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        source_pin: "output",
        target_pin: "input"
      })

    {:ok, connection} = Flows.create_connection(flow, source_node, target_node, attrs)
    connection
  end

  defp overridden_field_names(attrs, allowed_fields) do
    for field <- allowed_fields,
        Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field)),
        do: Atom.to_string(field)
  end

  defp normalize_fixture_attrs(attrs, allowed_fields) do
    Enum.reduce(allowed_fields, %{}, fn field, normalized ->
      cond do
        Map.has_key?(attrs, field) -> Map.put(normalized, field, Map.fetch!(attrs, field))
        Map.has_key?(attrs, Atom.to_string(field)) -> Map.put(normalized, field, Map.fetch!(attrs, Atom.to_string(field)))
        true -> normalized
      end
    end)
  end
end
