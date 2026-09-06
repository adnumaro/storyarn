defmodule Storyarn.Flows.Editor.Commands.CompositionSourceUpdate do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Editor.Commands.SequenceCompositionWrite
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

  @spec set(integer(), integer() | String.t() | nil) ::
          {:ok, FlowNode.t()} | {:error, atom() | tuple() | Ecto.Changeset.t()}
  def set(owner_id, source_id) when is_integer(owner_id) do
    with {:ok, source_id} <- normalize_optional_id(source_id) do
      Repo.transaction(fn -> persist(owner_id, source_id) end)
    end
  end

  def set(_owner_id, source_id), do: {:error, {:invalid_composition_source, source_id}}

  defp persist(owner_id, source_id) do
    with {:ok, %{flow: flow, node: owner}} <- SequenceCompositionWrite.lock_owner(owner_id),
         {:ok, nodes} <- lock_composition_nodes(flow.id),
         :ok <- validate_composition_source(owner, source_id, nodes),
         {:ok, updated} <-
           owner
           |> FlowNode.composition_source_changeset(%{composition_source_id: source_id})
           |> Repo.update(),
         :ok <- SequenceCompositionWrite.validate_dependents(flow.id, owner_id) do
      updated
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_composition_nodes(flow_id) do
    nodes =
      Repo.all(
        from(node in FlowNode,
          where:
            node.flow_id == ^flow_id and node.type in ["sequence", "dialogue"] and
              is_nil(node.deleted_at),
          order_by: [asc: node.id],
          lock: "FOR UPDATE"
        )
      )

    {:ok, Map.new(nodes, &{&1.id, &1})}
  end

  defp validate_composition_source(_owner, nil, _nodes), do: :ok

  defp validate_composition_source(owner, source_id, nodes) do
    case Map.get(nodes, source_id) do
      %FlowNode{} ->
        if composition_cycle?(owner.id, source_id, nodes),
          do: {:error, :composition_cycle},
          else: :ok

      nil ->
        {:error, {:invalid_composition_source, source_id}}
    end
  end

  defp composition_cycle?(owner_id, source_id, nodes), do: composition_cycle?(owner_id, source_id, nodes, MapSet.new())

  defp composition_cycle?(owner_id, owner_id, _nodes, _visited), do: true
  defp composition_cycle?(_owner_id, nil, _nodes, _visited), do: false

  defp composition_cycle?(owner_id, source_id, nodes, visited) do
    if MapSet.member?(visited, source_id) do
      true
    else
      case Map.get(nodes, source_id) do
        %FlowNode{composition_source_id: next_id} ->
          composition_cycle?(owner_id, next_id, nodes, MapSet.put(visited, source_id))

        nil ->
          false
      end
    end
  end

  defp normalize_optional_id(value) when value in [nil, ""], do: {:ok, nil}
  defp normalize_optional_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_optional_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, {:invalid_composition_source, value}}
    end
  end

  defp normalize_optional_id(value), do: {:error, {:invalid_composition_source, value}}
end
