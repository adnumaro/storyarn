defmodule Storyarn.Flows.Editor.Commands.SequenceCreate do
  @moduledoc false

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.References
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @spec create_sequence(integer(), map()) ::
          {:ok, FlowNode.t()} | {:error, Ecto.Changeset.t()}
  def create_sequence(flow_id, attrs) do
    attrs = normalize_keys(attrs)

    fn -> insert_in_transaction(flow_id, attrs) end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  @doc false
  @spec insert_in_transaction(integer(), map()) :: {FlowNode.t(), integer()}
  def insert_in_transaction(flow_id, attrs) do
    node_attrs = %{
      "type" => "sequence",
      "position_x" => Map.get(attrs, "position_x", 0.0),
      "position_y" => Map.get(attrs, "position_y", 0.0),
      "parent_id" => Map.get(attrs, "parent_id")
    }

    config_attrs = %{
      "name" => Map.get(attrs, "name"),
      "width" => Map.get(attrs, "width", 300.0),
      "height" => Map.get(attrs, "height", 200.0)
    }

    with {:ok, %{flow: flow, project_id: project_id}} <-
           References.lock_active_flow_for_write(flow_id),
         {:ok, parent_id} <-
           References.lock_node_parent(flow.id, node_attrs["parent_id"]),
         node_attrs = Map.put(node_attrs, "parent_id", parent_id),
         {:ok, node} <-
           %FlowNode{flow_id: flow_id}
           |> FlowNode.create_changeset(node_attrs)
           |> Repo.insert(),
         {:ok, config} <-
           %SequenceConfig{}
           |> SequenceConfig.create_changeset(Map.put(config_attrs, "flow_node_id", node.id))
           |> Repo.insert() do
      {%{node | sequence_config: config}, project_id}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp broadcast_sequence_result({:ok, {sequence, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, sequence}
  end

  defp broadcast_sequence_result(result), do: result
end
