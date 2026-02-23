defmodule Storyarn.Flows.NodeUpdate do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{FlowNode, NodeCrud, VariableReferenceTracker}
  alias Storyarn.Localization.TextExtractor
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.ReferenceTracker

  def update_node(%FlowNode{} = node, attrs) do
    node
    |> FlowNode.update_changeset(attrs)
    |> Repo.update()
  end

  def update_node_position(%FlowNode{} = node, attrs) do
    node
    |> FlowNode.position_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Batch-updates positions for multiple nodes in a single transaction.
  Accepts a flow_id and a list of maps with :id, :position_x, :position_y.
  Returns {:ok, count} with the number of updated nodes.
  """
  def batch_update_positions(flow_id, positions) when is_list(positions) do
    now = TimeHelpers.now()

    Repo.transaction(fn ->
      Enum.each(positions, fn %{id: node_id, position_x: x, position_y: y} ->
        from(n in FlowNode,
          where: n.id == ^node_id and n.flow_id == ^flow_id and is_nil(n.deleted_at)
        )
        |> Repo.update_all(set: [position_x: x, position_y: y, updated_at: now])
      end)

      length(positions)
    end)
  end

  def update_node_data(%FlowNode{type: "hub"} = node, data) do
    update_hub_node_data(node, data)
  end

  def update_node_data(%FlowNode{} = node, data) do
    case do_update_node_data(node, data) do
      {:ok, updated_node} -> {:ok, updated_node, %{renamed_jumps: 0}}
      error -> error
    end
  end

  def change_node(%FlowNode{} = node, attrs \\ %{}) do
    FlowNode.update_changeset(node, attrs)
  end

  defp update_hub_node_data(node, data) do
    hub_id = data["hub_id"]

    cond do
      hub_id == nil || hub_id == "" ->
        {:error, :hub_id_required}

      NodeCrud.hub_id_exists?(node.flow_id, hub_id, node.id) ->
        {:error, :hub_id_not_unique}

      true ->
        do_update_hub_data(node, data, hub_id)
    end
  end

  defp do_update_hub_data(node, data, hub_id) do
    old_hub_id = node.data["hub_id"]

    case do_update_node_data(node, data) do
      {:ok, updated_node} ->
        renamed_count =
          if old_hub_id != hub_id,
            do: cascade_hub_id_rename(node.flow_id, old_hub_id, hub_id),
            else: 0

        {:ok, updated_node, %{renamed_jumps: renamed_count}}

      error ->
        error
    end
  end

  defp do_update_node_data(node, data) do
    Repo.transaction(fn ->
      updated_node =
        node
        |> FlowNode.data_changeset(%{data: data})
        |> Repo.update!()

      ReferenceTracker.update_flow_node_references(updated_node)
      VariableReferenceTracker.update_references(updated_node)
      TextExtractor.extract_flow_node(updated_node)
      updated_node
    end)
  end

  defp cascade_hub_id_rename(flow_id, old_hub_id, new_hub_id)
       when is_binary(old_hub_id) and old_hub_id != "" do
    now = Storyarn.Shared.TimeHelpers.now()

    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "jump",
        where: fragment("?->>'target_hub_id' = ?", n.data, ^old_hub_id),
        update: [
          set: [
            data:
              fragment("jsonb_set(?, '{target_hub_id}', to_jsonb(?::text))", n.data, ^new_hub_id),
            updated_at: ^now
          ]
        ]
      )

    {count, _} = Repo.update_all(query, [])
    count
  end

  defp cascade_hub_id_rename(_, _, _), do: 0
end
