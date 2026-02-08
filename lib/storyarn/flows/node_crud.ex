defmodule Storyarn.Flows.NodeCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode, VariableReferenceTracker}
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

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

      "subflow" ->
        validate_and_insert_subflow(flow, attrs)

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

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

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

  @doc """
  Lists all Exit nodes for a given flow.
  Returns a list of maps with :id, :label, and :is_success.
  Used by subflow nodes to generate dynamic output pins.
  """
  def list_exit_nodes_for_flow(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "exit",
      select: %{
        id: n.id,
        label: fragment("?->>'label'", n.data),
        is_success: fragment("(?->>'is_success')::boolean", n.data)
      },
      order_by: [asc: n.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Finds all subflow nodes that reference a given flow within the same project.
  Used for stale detection when a flow is deleted or exits change.
  """
  def list_subflow_nodes_referencing(flow_id, project_id) do
    flow_id_str = to_string(flow_id)

    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id,
      where: n.type == "subflow",
      where: fragment("?->>'referenced_flow_id' = ?", n.data, ^flow_id_str),
      select: %{id: n.id, flow_id: n.flow_id}
    )
    |> Repo.all()
  end

  @doc """
  Checks if setting source_flow_id to reference target_flow_id would create a circular reference.
  Walks the subflow reference graph from target_flow_id to detect cycles.
  """
  def has_circular_reference?(source_flow_id, target_flow_id) do
    do_check_circular(source_flow_id, target_flow_id, MapSet.new(), 0)
  end

  defp do_check_circular(source_flow_id, current_flow_id, visited, depth) do
    cond do
      depth > 20 -> true
      current_flow_id == source_flow_id -> true
      MapSet.member?(visited, current_flow_id) -> false
      true ->
        visited = MapSet.put(visited, current_flow_id)

        # Find all subflow nodes in current_flow_id and check their references
        referenced_flow_ids =
          from(n in FlowNode,
            where: n.flow_id == ^current_flow_id and n.type == "subflow",
            where: not is_nil(fragment("?->>'referenced_flow_id'", n.data)),
            where: fragment("?->>'referenced_flow_id' ~ '^[0-9]+$'", n.data),
            select: fragment("(?->>'referenced_flow_id')::integer", n.data)
          )
          |> Repo.all()

        Enum.any?(referenced_flow_ids, fn ref_id ->
          do_check_circular(source_flow_id, ref_id, visited, depth + 1)
        end)
    end
  end

  defp validate_and_insert_subflow(%Flow{} = flow, attrs) do
    referenced_flow_id = get_in(attrs, ["data", "referenced_flow_id"])

    cond do
      # Allow creation with nil reference (user will set it later)
      is_nil(referenced_flow_id) || referenced_flow_id == "" ->
        insert_node(flow, attrs)

      # Reject unparseable IDs
      is_nil(safe_to_integer(referenced_flow_id)) ->
        {:error, :invalid_reference}

      # Cannot reference the same flow
      to_string(referenced_flow_id) == to_string(flow.id) ->
        {:error, :self_reference}

      # Check circular reference
      has_circular_reference?(flow.id, safe_to_integer(referenced_flow_id)) ->
        {:error, :circular_reference}

      true ->
        insert_node(flow, attrs)
    end
  end

  @doc """
  Pre-fetches all referenced flow data for subflow nodes in a single batch.
  Returns a map of %{flow_id => %{flow: flow, exit_labels: [...]}} for valid refs,
  or an empty map if there are no subflow nodes.
  """
  def batch_resolve_subflow_data(nodes) do
    ref_ids =
      nodes
      |> Enum.filter(&(&1.type == "subflow"))
      |> Enum.map(& &1.data["referenced_flow_id"])
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.map(&safe_to_integer/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ref_ids == [] do
      %{}
    else
      flows =
        from(f in Flow, where: f.id in ^ref_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      exits =
        from(n in FlowNode,
          where: n.flow_id in ^ref_ids and n.type == "exit",
          select: %{
            flow_id: n.flow_id,
            id: n.id,
            label: fragment("?->>'label'", n.data),
            is_success: fragment("(?->>'is_success')::boolean", n.data)
          },
          order_by: [asc: n.inserted_at]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.flow_id)

      Map.new(ref_ids, fn id ->
        {id, %{flow: Map.get(flows, id), exit_labels: Map.get(exits, id, [])}}
      end)
    end
  end

  @doc """
  Resolves subflow node data by enriching it with referenced flow info.
  Uses pre-fetched cache from batch_resolve_subflow_data/1.
  """
  def resolve_subflow_data(data, subflow_cache) do
    case data["referenced_flow_id"] do
      nil ->
        data

      "" ->
        data

      ref_id ->
        case safe_to_integer(ref_id) do
          nil ->
            data

          int_id ->
            cached = Map.get(subflow_cache, int_id, :not_cached)
            resolve_subflow_from_cached(data, int_id, cached)
        end
    end
  end

  defp resolve_subflow_from_cached(data, int_id, :not_cached) do
    # Fallback for single-node resolution (no batch cache available)
    case Repo.get(Flow, int_id) do
      nil ->
        mark_stale_subflow(data)

      %Flow{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        mark_stale_subflow(data)

      flow ->
        exit_labels = list_exit_nodes_for_flow(flow.id)
        enrich_subflow_data(data, flow, exit_labels)
    end
  end

  defp resolve_subflow_from_cached(data, _int_id, %{flow: nil}),
    do: mark_stale_subflow(data)

  defp resolve_subflow_from_cached(data, _int_id, %{flow: %Flow{deleted_at: d}})
       when not is_nil(d),
       do: mark_stale_subflow(data)

  defp resolve_subflow_from_cached(data, _int_id, %{flow: flow, exit_labels: exit_labels}),
    do: enrich_subflow_data(data, flow, exit_labels)

  defp enrich_subflow_data(data, flow, exit_labels) do
    data
    |> Map.put("stale_reference", false)
    |> Map.put("referenced_flow_name", flow.name)
    |> Map.put("referenced_flow_shortcut", flow.shortcut)
    |> Map.put("exit_labels", exit_labels)
  end

  defp mark_stale_subflow(data) do
    data
    |> Map.put("stale_reference", true)
    |> Map.put("referenced_flow_name", nil)
    |> Map.put("referenced_flow_shortcut", nil)
    |> Map.put("exit_labels", [])
  end

  @doc """
  Safely converts a string or integer to integer.
  Returns nil if the value cannot be parsed.
  """
  def safe_to_integer(value) when is_integer(value), do: value

  def safe_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def safe_to_integer(_), do: nil

end
