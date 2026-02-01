defmodule Storyarn.FlowsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  flows via the `Storyarn.Flows` context.
  """

  alias Storyarn.Flows
  alias Storyarn.ProjectsFixtures

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
