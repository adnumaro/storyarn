defmodule Storyarn.FlowsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  flows via the `Storyarn.Flows` context.
  """

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.ProjectsFixtures
  alias Storyarn.Repo

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
end
