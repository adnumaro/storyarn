defmodule Storyarn.Flows.NodeCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode, VariableReferenceTracker}
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Repo

  def list_nodes(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id,
      order_by: [asc: n.inserted_at]
    )
    |> Repo.all()
  end

  def get_node(flow_id, node_id) do
    FlowNode
    |> where(flow_id: ^flow_id, id: ^node_id)
    |> preload([:outgoing_connections, :incoming_connections])
    |> Repo.one()
  end

  def get_node!(flow_id, node_id) do
    FlowNode
    |> where(flow_id: ^flow_id, id: ^node_id)
    |> preload([:outgoing_connections, :incoming_connections])
    |> Repo.one!()
  end

  def get_node_by_id!(node_id) do
    Repo.get!(FlowNode, node_id)
  end

  def create_node(%Flow{} = flow, attrs) do
    attrs = stringify_keys(attrs)

    case attrs["type"] do
      "entry" ->
        if has_entry_node?(flow.id) do
          {:error, :entry_node_exists}
        else
          insert_node(flow, attrs)
        end

      "hub" ->
        hub_id = get_in(attrs, ["data", "hub_id"])
        hub_id = if hub_id == nil || hub_id == "", do: generate_hub_id(flow.id), else: hub_id

        if hub_id_exists?(flow.id, hub_id, nil) do
          {:error, :hub_id_not_unique}
        else
          updated_data = Map.put(attrs["data"] || %{}, "hub_id", hub_id)
          insert_node(flow, Map.put(attrs, "data", updated_data))
        end

      _ ->
        insert_node(flow, attrs)
    end
  end

  defp insert_node(%Flow{} = flow, attrs) do
    %FlowNode{flow_id: flow.id}
    |> FlowNode.create_changeset(attrs)
    |> Repo.insert()
  end

  defp has_entry_node?(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "entry"
    )
    |> Repo.exists?()
  end

  defp is_last_exit_node?(node) do
    from(n in FlowNode,
      where: n.flow_id == ^node.flow_id and n.type == "exit"
    )
    |> Repo.aggregate(:count, :id) <= 1
  end

  @doc """
  Checks if a hub_id already exists in a flow (excluding a specific node).
  """
  def hub_id_exists?(flow_id, hub_id, exclude_node_id) do
    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "hub",
        where: fragment("?->>'hub_id' = ?", n.data, ^hub_id)
      )

    query =
      if exclude_node_id do
        where(query, [n], n.id != ^exclude_node_id)
      else
        query
      end

    Repo.exists?(query)
  end

  @doc """
  Lists all hub nodes in a flow with their hub_ids.
  Useful for populating Jump node target dropdown.
  """
  def list_hubs(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "hub",
      select: %{
        id: n.id,
        hub_id: fragment("?->>'hub_id'", n.data),
        label: fragment("?->>'label'", n.data)
      },
      order_by: [asc: fragment("?->>'hub_id'", n.data)]
    )
    |> Repo.all()
  end

  @doc """
  Finds a hub node in a flow by its hub_id.
  Returns nil if not found.
  """
  def get_hub_by_hub_id(flow_id, hub_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "hub",
      where: fragment("?->>'hub_id' = ?", n.data, ^hub_id)
    )
    |> Repo.one()
  end

  defp generate_hub_id(flow_id) do
    max_suffix =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "hub",
        where: fragment("?->>'hub_id' ~ '^hub_[0-9]+$'", n.data),
        select:
          fragment("max(cast(substring(?->>'hub_id' from 'hub_([0-9]+)') as integer))", n.data)
      )
      |> Repo.one()

    "hub_#{(max_suffix || 0) + 1}"
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

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

  def update_node_data(%FlowNode{} = node, data) do
    if node.type == "hub" do
      hub_id = data["hub_id"]

      cond do
        hub_id == nil || hub_id == "" ->
          {:error, :hub_id_required}

        hub_id_exists?(node.flow_id, hub_id, node.id) ->
          {:error, :hub_id_not_unique}

        true ->
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
    else
      case do_update_node_data(node, data) do
        {:ok, updated_node} -> {:ok, updated_node, %{renamed_jumps: 0}}
        error -> error
      end
    end
  end

  defp do_update_node_data(node, data) do
    result =
      node
      |> FlowNode.data_changeset(%{data: data})
      |> Repo.update()

    case result do
      {:ok, updated_node} ->
        ReferenceTracker.update_flow_node_references(updated_node)
        VariableReferenceTracker.update_references(updated_node)
        {:ok, updated_node}

      error ->
        error
    end
  end

  def delete_node(%FlowNode{} = node) do
    cond do
      node.type == "entry" ->
        {:error, :cannot_delete_entry_node}

      node.type == "exit" && is_last_exit_node?(node) ->
        {:error, :cannot_delete_last_exit}

      true ->
        Repo.transaction(fn ->
          orphaned_count =
            if node.type == "hub" do
              clear_orphaned_jumps(node.flow_id, node.data["hub_id"])
            else
              0
            end

          ReferenceTracker.delete_flow_node_references(node.id)
          VariableReferenceTracker.delete_references(node.id)

          case Repo.delete(node) do
            {:ok, deleted_node} -> {deleted_node, %{orphaned_jumps: orphaned_count}}
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
        |> case do
          {:ok, {deleted_node, meta}} -> {:ok, deleted_node, meta}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp cascade_hub_id_rename(flow_id, old_hub_id, new_hub_id)
       when is_binary(old_hub_id) and old_hub_id != "" do
    now = DateTime.utc_now()

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

  defp clear_orphaned_jumps(flow_id, hub_id) when is_binary(hub_id) and hub_id != "" do
    now = DateTime.utc_now()

    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "jump",
        where: fragment("?->>'target_hub_id' = ?", n.data, ^hub_id),
        update: [
          set: [
            data: fragment("jsonb_set(?, '{target_hub_id}', '\"\"'::jsonb)", n.data),
            updated_at: ^now
          ]
        ]
      )

    {count, _} = Repo.update_all(query, [])

    count
  end

  defp clear_orphaned_jumps(_flow_id, _hub_id), do: 0

  def change_node(%FlowNode{} = node, attrs \\ %{}) do
    FlowNode.update_changeset(node, attrs)
  end

  @doc """
  Lists jump nodes that reference a given hub_id within a flow.
  Returns a list of maps with :id and :label (or position info).
  """
  def list_referencing_jumps(flow_id, hub_id) when is_binary(hub_id) and hub_id != "" do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "jump",
      where: fragment("?->>'target_hub_id' = ?", n.data, ^hub_id),
      order_by: [asc: n.position_y, asc: n.position_x],
      select: %{id: n.id, position_x: n.position_x, position_y: n.position_y}
    )
    |> Repo.all()
  end

  def list_referencing_jumps(_flow_id, _hub_id), do: []

  def count_nodes_by_type(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id,
      group_by: n.type,
      select: {n.type, count(n.id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
