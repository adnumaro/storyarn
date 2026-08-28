defmodule Storyarn.Flows.NodeCreate do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Storyarn.Flows.Editor.Adapters.Postgres.CircularReferenceQuery
  alias Storyarn.Flows.Editor.Commands.ItemCapacity
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Localization
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.NodeUpdate
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo

  # Prevents infinite recursion in circular reference detection
  @max_reference_depth 20

  def create_node(%Flow{} = flow, attrs) do
    result = create_node_without_dashboard_broadcast(flow, attrs)

    case result do
      {:ok, _node} ->
        Storyarn.Platform.Collaboration.broadcast_dashboard_change(flow.project_id, :flows)

      _ ->
        :ok
    end

    result
  end

  @doc false
  def create_node_without_dashboard_broadcast(%Flow{} = flow, attrs) do
    attrs = stringify_keys(attrs)

    fn -> create_node_in_transaction(flow, attrs) end
    |> Repo.transaction()
    |> normalize_item_limit_result()
  end

  defp create_node_in_transaction(flow, attrs) do
    attrs =
      if is_map(attrs["data"]) do
        attrs
      else
        Map.put(attrs, "data", NodeTypes.default_data(attrs["type"]))
      end

    with {:ok,
          %{
            project: locked_project,
            project_id: project_id,
            flow: locked_flow
          }} <-
           References.lock_active_flow_for_write(flow),
         :ok <- ItemCapacity.can_create_item?(locked_project),
         {:ok, parent_id} <-
           References.lock_node_parent(
             locked_flow.id,
             attrs["parent_id"]
           ),
         {:ok, normalized_data} <-
           References.lock_and_normalize_node_references(
             project_id,
             locked_flow.id,
             attrs["type"],
             attrs["data"]
           ) do
      attrs
      |> Map.put("parent_id", parent_id)
      |> Map.put("data", normalized_data)
      |> then(&create_and_reconcile_node(locked_flow, &1))
    else
      {:error, reason, details} ->
        Repo.rollback({reason, details})

      {:error, {:invalid_project_reference, :referenced_flow_id, _value} = reason} ->
        case References.normalize_optional_id(get_in(attrs, ["data", "referenced_flow_id"])) do
          :error -> Repo.rollback(:invalid_reference)
          {:ok, _id} -> Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp normalize_item_limit_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_item_limit_result(result), do: result

  defp create_and_reconcile_node(flow, attrs) do
    case create_node_by_type(flow, attrs) do
      {:ok, node} -> NodeUpdate.reconcile_persisted_node(node, flow.project_id)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp create_node_by_type(flow, attrs) do
    case attrs["type"] do
      "entry" -> create_entry_node(flow, attrs)
      "hub" -> create_hub_node(flow, attrs)
      "sequence" -> {:error, :sequence_requires_sequence_api}
      _ -> insert_node(flow, attrs)
    end
  end

  defp create_entry_node(flow, attrs) do
    Repo.transaction(fn ->
      lock_flow!(flow.id)

      if has_entry_node?(flow.id) do
        Repo.rollback(:entry_node_exists)
      else
        insert_node_or_rollback(flow, attrs)
      end
    end)
  end

  defp create_hub_node(flow, attrs) do
    with {:ok, hub_id} <- resolve_hub_id(flow.id, get_in(attrs, ["data", "hub_id"])) do
      Repo.transaction(fn -> create_hub_node_transaction(flow, attrs, hub_id) end)
    end
  end

  defp create_hub_node_transaction(flow, attrs, hub_id) do
    lock_flow!(flow.id)

    if NodeCrud.hub_id_exists?(flow.id, hub_id, nil) do
      Repo.rollback(:hub_id_not_unique)
    else
      updated_data = Map.put(attrs["data"] || %{}, "hub_id", hub_id)
      insert_node_or_rollback(flow, Map.put(attrs, "data", updated_data))
    end
  end

  defp resolve_hub_id(flow_id, hub_id) when hub_id in [nil, ""], do: {:ok, generate_hub_id(flow_id)}

  defp resolve_hub_id(_flow_id, hub_id) when is_binary(hub_id) do
    if String.trim(hub_id) == "", do: {:error, :hub_id_required}, else: {:ok, hub_id}
  end

  defp resolve_hub_id(_flow_id, _hub_id), do: {:error, :hub_id_required}

  defp insert_node_or_rollback(flow, attrs) do
    case insert_node(flow, attrs) do
      {:ok, node} -> node
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # Acquires a row-level lock on the flow to serialize concurrent node creation
  defp lock_flow!(flow_id) do
    Repo.one!(from(f in Flow, where: f.id == ^flow_id, lock: "FOR UPDATE"))
  end

  defp insert_node(%Flow{} = flow, attrs) do
    changeset = FlowNode.create_changeset(%FlowNode{flow_id: flow.id}, attrs)
    type = Ecto.Changeset.get_field(changeset, :type)
    data = Ecto.Changeset.get_field(changeset, :data)

    changeset
    |> Ecto.Changeset.put_change(:word_count, Localization.node_word_count(type, data))
    |> Ecto.Changeset.put_change(
      :derivatives_fingerprint,
      NodeUpdate.derivatives_fingerprint(type, data)
    )
    |> Repo.insert()
  end

  defp has_entry_node?(flow_id) do
    Repo.exists?(from(n in FlowNode, where: n.flow_id == ^flow_id and n.type == "entry" and is_nil(n.deleted_at)))
  end

  defp generate_hub_id(flow_id) do
    max_suffix =
      Repo.one(
        from(n in FlowNode,
          where: n.flow_id == ^flow_id and n.type == "hub" and is_nil(n.deleted_at),
          where: fragment("?->>'hub_id' ~ '^hub_[0-9]+$'", n.data),
          select: fragment("max(cast(substring(?->>'hub_id' from 'hub_([0-9]+)') as integer))", n.data)
        )
      )

    "hub_#{(max_suffix || 0) + 1}"
  end

  @doc """
  Checks if setting source_flow_id to reference target_flow_id would create a circular reference.
  Walks the subflow reference graph from target_flow_id to detect cycles.
  """
  def has_circular_reference?(source_flow_id, target_flow_id) do
    do_check_circular(source_flow_id, target_flow_id, MapSet.new(), 0)
  end

  @doc false
  @spec circular_reference_pairs([{integer(), integer()}]) ::
          MapSet.t({integer(), integer()})
  def circular_reference_pairs([]), do: MapSet.new()

  def circular_reference_pairs(pairs) when is_list(pairs) do
    pairs =
      pairs
      |> Enum.uniq()
      |> Enum.sort()

    CircularReferenceQuery.circular_pairs(pairs, @max_reference_depth)
  end

  defp do_check_circular(source_flow_id, current_flow_id, visited, depth) do
    cond do
      depth > @max_reference_depth ->
        true

      current_flow_id == source_flow_id ->
        true

      MapSet.member?(visited, current_flow_id) ->
        false

      true ->
        visited = MapSet.put(visited, current_flow_id)
        referenced_flow_ids = get_referenced_flow_ids(current_flow_id)

        Enum.any?(referenced_flow_ids, fn ref_id ->
          do_check_circular(source_flow_id, ref_id, visited, depth + 1)
        end)
    end
  end

  defp get_referenced_flow_ids(flow_id) do
    # Subflow references (exclude soft-deleted nodes)
    subflow_refs =
      Repo.all(
        from(n in FlowNode,
          where: n.flow_id == ^flow_id and n.type == "subflow" and is_nil(n.deleted_at),
          where: not is_nil(fragment("?->>'referenced_flow_id'", n.data)),
          where: fragment("?->>'referenced_flow_id' ~ '^[0-9]+$'", n.data),
          select: fragment("(?->>'referenced_flow_id')::integer", n.data)
        )
      )

    # Exit flow references (exclude soft-deleted nodes)
    exit_refs =
      Repo.all(
        from(n in FlowNode,
          where: n.flow_id == ^flow_id and n.type == "exit" and is_nil(n.deleted_at),
          where: fragment("?->>'exit_mode'", n.data) == "flow_reference",
          where: not is_nil(fragment("?->>'referenced_flow_id'", n.data)),
          where: fragment("?->>'referenced_flow_id' ~ '^[0-9]+$'", n.data),
          select: fragment("(?->>'referenced_flow_id')::integer", n.data)
        )
      )

    (subflow_refs ++ exit_refs) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp stringify_keys(map), do: MapAccess.stringify_keys(map)
end
