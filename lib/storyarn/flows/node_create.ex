defmodule Storyarn.Flows.NodeCreate do
  @moduledoc false

  # Prevents infinite recursion in circular reference detection
  @max_reference_depth 20

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode, NodeCrud}
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

  def create_node(%Flow{} = flow, attrs) do
    attrs = stringify_keys(attrs)

    case attrs["type"] do
      "entry" -> create_entry_node(flow, attrs)
      "hub" -> create_hub_node(flow, attrs)
      "subflow" -> validate_and_insert_subflow(flow, attrs)
      _ -> insert_node(flow, attrs)
    end
  end

  defp create_entry_node(flow, attrs) do
    if has_entry_node?(flow.id) do
      {:error, :entry_node_exists}
    else
      insert_node(flow, attrs)
    end
  end

  defp create_hub_node(flow, attrs) do
    hub_id = get_in(attrs, ["data", "hub_id"])
    hub_id = if hub_id == nil || hub_id == "", do: generate_hub_id(flow.id), else: hub_id

    if NodeCrud.hub_id_exists?(flow.id, hub_id, nil) do
      {:error, :hub_id_not_unique}
    else
      updated_data = Map.put(attrs["data"] || %{}, "hub_id", hub_id)
      insert_node(flow, Map.put(attrs, "data", updated_data))
    end
  end

  def insert_node(%Flow{} = flow, attrs) do
    %FlowNode{flow_id: flow.id}
    |> FlowNode.create_changeset(attrs)
    |> Repo.insert()
  end

  defp has_entry_node?(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "entry" and is_nil(n.deleted_at)
    )
    |> Repo.exists?()
  end

  defp generate_hub_id(flow_id) do
    max_suffix =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "hub" and is_nil(n.deleted_at),
        where: fragment("?->>'hub_id' ~ '^hub_[0-9]+$'", n.data),
        select:
          fragment("max(cast(substring(?->>'hub_id' from 'hub_([0-9]+)') as integer))", n.data)
      )
      |> Repo.one()

    "hub_#{(max_suffix || 0) + 1}"
  end

  defp validate_and_insert_subflow(%Flow{} = flow, attrs) do
    referenced_flow_id = get_in(attrs, ["data", "referenced_flow_id"])

    cond do
      # Allow creation with nil reference (user will set it later)
      is_nil(referenced_flow_id) || referenced_flow_id == "" ->
        insert_node(flow, attrs)

      # Reject unparseable IDs
      is_nil(NodeCrud.safe_to_integer(referenced_flow_id)) ->
        {:error, :invalid_reference}

      # Cannot reference the same flow
      to_string(referenced_flow_id) == to_string(flow.id) ->
        {:error, :self_reference}

      # Check circular reference
      has_circular_reference?(flow.id, NodeCrud.safe_to_integer(referenced_flow_id)) ->
        {:error, :circular_reference}

      true ->
        insert_node(flow, attrs)
    end
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
    # Subflow references
    subflow_refs =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "subflow",
        where: not is_nil(fragment("?->>'referenced_flow_id'", n.data)),
        where: fragment("?->>'referenced_flow_id' ~ '^[0-9]+$'", n.data),
        select: fragment("(?->>'referenced_flow_id')::integer", n.data)
      )
      |> Repo.all()

    # Exit flow references
    exit_refs =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "exit",
        where: fragment("?->>'exit_mode'", n.data) == "flow_reference",
        where: not is_nil(fragment("?->>'referenced_flow_id'", n.data)),
        where: fragment("?->>'referenced_flow_id' ~ '^[0-9]+$'", n.data),
        select: fragment("(?->>'referenced_flow_id')::integer", n.data)
      )
      |> Repo.all()

    (subflow_refs ++ exit_refs) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)
end
