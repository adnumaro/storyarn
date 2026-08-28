defmodule Storyarn.Projects.FlowReferenceResolver do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Repo

  def batch_resolve_subflow_data(nodes, project_id \\ nil) do
    ref_ids = referenced_ids(nodes, "subflow")

    if ref_ids == [] do
      %{}
    else
      flow_query = from(flow in FlowRecord, where: flow.id in ^ref_ids)
      flow_query = if project_id, do: where(flow_query, [flow], flow.project_id == ^project_id), else: flow_query
      flows = flow_query |> Repo.all() |> Map.new(&{&1.id, &1})

      exits =
        from(node in FlowNodeRecord,
          where: node.flow_id in ^ref_ids and node.type == "exit" and is_nil(node.deleted_at),
          select: %{
            flow_id: node.flow_id,
            id: node.id,
            label: fragment("?->>'label'", node.data),
            outcome_tags: fragment("?->'outcome_tags'", node.data),
            outcome_color: fragment("coalesce(?->>'outcome_color', '#22c55e')", node.data),
            exit_mode: fragment("coalesce(?->>'exit_mode', 'terminal')", node.data)
          },
          order_by: [asc: node.inserted_at, asc: node.id]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.flow_id)

      Map.new(ref_ids, fn id ->
        {id, %{flow: Map.get(flows, id), exit_labels: Map.get(exits, id, [])}}
      end)
    end
  end

  def resolve_subflow_data(data, subflow_cache) do
    case safe_to_integer(data["referenced_flow_id"]) do
      nil -> data
      id -> resolve_subflow_from_cached(data, id, Map.get(subflow_cache, id, :not_cached))
    end
  end

  def batch_resolve_exit_data(nodes, project_id \\ nil) do
    ref_ids =
      nodes
      |> Enum.filter(&(&1.type == "exit" and (&1.data || %{})["exit_mode"] == "flow_reference"))
      |> Enum.map(& &1.data["referenced_flow_id"])
      |> Enum.map(&safe_to_integer/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ref_ids == [] do
      %{}
    else
      query = from(flow in FlowRecord, where: flow.id in ^ref_ids and is_nil(flow.deleted_at))
      query = if project_id, do: where(query, [flow], flow.project_id == ^project_id), else: query
      found = query |> Repo.all() |> Map.new(&{&1.id, &1})
      Map.new(ref_ids, &{&1, Map.get(found, &1)})
    end
  end

  def resolve_exit_data(%{"exit_mode" => "flow_reference"} = data, project_id, exit_cache) do
    case safe_to_integer(data["referenced_flow_id"]) do
      nil ->
        resolve_exit_data(data, project_id)

      id ->
        case Map.fetch(exit_cache, id) do
          {:ok, nil} -> mark_stale_reference(data)
          {:ok, flow} -> enrich_exit_reference(data, flow)
          :error -> resolve_exit_data(data, project_id)
        end
    end
  end

  def resolve_exit_data(data, _project_id, _exit_cache), do: data

  def resolve_exit_data(%{"exit_mode" => "flow_reference"} = data, project_id) do
    case safe_to_integer(data["referenced_flow_id"]) do
      nil -> data
      id -> resolve_exit_flow_reference(data, id, project_id)
    end
  end

  def resolve_exit_data(data, _project_id), do: data

  defp referenced_ids(nodes, type) do
    nodes
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(&(&1.data || %{})["referenced_flow_id"])
    |> Enum.map(&safe_to_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp resolve_subflow_from_cached(data, id, :not_cached) do
    case Repo.get(FlowRecord, id) do
      %FlowRecord{deleted_at: nil} = flow -> enrich_subflow_data(data, flow, list_exit_nodes(flow.id))
      _missing_or_deleted -> mark_stale_subflow(data)
    end
  end

  defp resolve_subflow_from_cached(data, _id, %{flow: %FlowRecord{deleted_at: nil} = flow, exit_labels: labels}),
    do: enrich_subflow_data(data, flow, labels)

  defp resolve_subflow_from_cached(data, _id, _missing_or_deleted), do: mark_stale_subflow(data)

  defp list_exit_nodes(flow_id) do
    Repo.all(
      from(node in FlowNodeRecord,
        where: node.flow_id == ^flow_id and node.type == "exit" and is_nil(node.deleted_at),
        select: %{
          id: node.id,
          label: fragment("?->>'label'", node.data),
          outcome_tags: fragment("?->'outcome_tags'", node.data),
          outcome_color: fragment("coalesce(?->>'outcome_color', '#22c55e')", node.data),
          exit_mode: fragment("coalesce(?->>'exit_mode', 'terminal')", node.data)
        },
        order_by: [asc: node.inserted_at, asc: node.id]
      )
    )
  end

  defp enrich_subflow_data(data, flow, exit_labels) do
    data
    |> Map.put("stale_reference", false)
    |> Map.put("referenced_flow_name", flow.name)
    |> Map.put("referenced_flow_shortcut", flow.shortcut)
    |> Map.put("exit_labels", exit_labels)
    |> Map.put("exit_pins", Enum.map(exit_labels, &"exit_#{&1.id}"))
  end

  defp mark_stale_subflow(data) do
    data
    |> Map.put("stale_reference", true)
    |> Map.put("referenced_flow_name", nil)
    |> Map.put("referenced_flow_shortcut", nil)
    |> Map.put("exit_labels", [])
    |> Map.put("exit_pins", [])
  end

  defp resolve_exit_flow_reference(data, flow_id, project_id) do
    query = from(flow in FlowRecord, where: flow.id == ^flow_id and is_nil(flow.deleted_at))
    query = if project_id, do: where(query, [flow], flow.project_id == ^project_id), else: query

    case Repo.one(query) do
      nil -> mark_stale_reference(data)
      flow -> enrich_exit_reference(data, flow)
    end
  end

  defp enrich_exit_reference(data, flow) do
    data
    |> Map.put("stale_reference", false)
    |> Map.put("referenced_flow_name", flow.name)
    |> Map.put("referenced_flow_shortcut", flow.shortcut)
  end

  defp mark_stale_reference(data) do
    data
    |> Map.put("stale_reference", true)
    |> Map.put("referenced_flow_name", nil)
    |> Map.put("referenced_flow_shortcut", nil)
  end

  defp safe_to_integer(value) when is_integer(value), do: value

  defp safe_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _invalid -> nil
    end
  end

  defp safe_to_integer(_value), do: nil
end
