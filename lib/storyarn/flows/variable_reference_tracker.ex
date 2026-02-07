defmodule Storyarn.Flows.VariableReferenceTracker do
  @moduledoc """
  Tracks which flow nodes read/write which variables (blocks).

  Called after every node data save. Extracts variable references from
  the node's structured data (condition rules -> reads, instruction
  assignments -> writes) and upserts them into the variable_references table.

  Stores `source_page` and `source_variable` alongside each reference so that
  staleness detection and repair can be done with simple SQL comparisons
  instead of scanning node JSON in Elixir.
  """

  import Ecto.Query

  alias Storyarn.Flows.{Flow, FlowNode, VariableReference}
  alias Storyarn.Pages.{Block, Page}
  alias Storyarn.Repo

  @doc """
  Updates variable references for a node after its data changes.
  Dispatches to the correct extractor based on node type.
  """
  @spec update_references(FlowNode.t()) :: :ok
  def update_references(%FlowNode{} = node) do
    refs =
      case node.type do
        "instruction" -> extract_write_refs(node)
        "condition" -> extract_read_refs(node)
        _ -> []
      end

    replace_references(node.id, refs)
  end

  @doc """
  Deletes all variable references for a node.
  Called when a node is deleted (as backup — DB cascade handles this too).
  """
  @spec delete_references(integer()) :: :ok
  def delete_references(node_id) do
    from(vr in VariableReference, where: vr.flow_node_id == ^node_id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Returns all variable references for a block, with flow/node info.
  Used by the page editor's variable usage section.
  """
  @spec get_variable_usage(integer(), integer()) :: [map()]
  def get_variable_usage(block_id, project_id) do
    from(vr in VariableReference,
      join: n in FlowNode, on: n.id == vr.flow_node_id,
      join: f in Flow, on: f.id == n.flow_id,
      where: vr.block_id == ^block_id,
      where: f.project_id == ^project_id,
      where: is_nil(f.deleted_at),
      select: %{
        kind: vr.kind,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut,
        node_id: n.id,
        node_type: n.type,
        node_data: n.data
      },
      order_by: [asc: vr.kind, asc: f.name]
    )
    |> Repo.all()
  end

  @doc """
  Counts variable references for a block, grouped by kind.
  Returns %{"read" => N, "write" => M}.
  """
  @spec count_variable_usage(integer()) :: map()
  def count_variable_usage(block_id) do
    from(vr in VariableReference,
      where: vr.block_id == ^block_id,
      group_by: vr.kind,
      select: {vr.kind, count(vr.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns variable usage for a block with stale detection.
  Each ref map gets an additional `:stale` boolean computed via SQL comparison
  of `source_page`/`source_variable` against the current page shortcut and
  block variable_name.

  Filters out references whose page or block has been soft-deleted.
  """
  @spec check_stale_references(integer(), integer()) :: [map()]
  def check_stale_references(block_id, project_id) do
    from(vr in VariableReference,
      join: n in FlowNode, on: n.id == vr.flow_node_id,
      join: f in Flow, on: f.id == n.flow_id,
      join: b in Block, on: b.id == vr.block_id,
      join: p in Page, on: p.id == b.page_id,
      where: vr.block_id == ^block_id,
      where: f.project_id == ^project_id,
      where: is_nil(f.deleted_at),
      where: is_nil(p.deleted_at),
      where: is_nil(b.deleted_at),
      select: %{
        kind: vr.kind,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut,
        node_id: n.id,
        node_type: n.type,
        node_data: n.data,
        stale: vr.source_page != p.shortcut or vr.source_variable != b.variable_name
      },
      order_by: [asc: vr.kind, asc: f.name]
    )
    |> Repo.all()
  end

  @doc """
  Repairs all stale variable references across a project.
  Updates node JSON to reflect current page shortcut + variable names.
  Returns `{:ok, count}` where count is the number of repaired nodes,
  or `{:error, reason}` if the transaction fails.
  """
  @spec repair_stale_references(integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def repair_stale_references(project_id) do
    # Get all variable references for this project with current block info + source fields
    refs_with_info =
      from(vr in VariableReference,
        join: n in FlowNode, on: n.id == vr.flow_node_id,
        join: f in Flow, on: f.id == n.flow_id,
        join: b in Block, on: b.id == vr.block_id,
        join: p in Page, on: p.id == b.page_id,
        where: f.project_id == ^project_id,
        where: is_nil(f.deleted_at),
        where: is_nil(p.deleted_at),
        where: is_nil(b.deleted_at),
        select: %{
          node_id: n.id,
          node_type: n.type,
          node_data: n.data,
          kind: vr.kind,
          block_id: vr.block_id,
          current_shortcut: p.shortcut,
          current_variable: b.variable_name,
          source_page: vr.source_page,
          source_variable: vr.source_variable
        }
      )
      |> Repo.all()

    # Group by node_id to batch repairs per node
    repairs_by_node =
      refs_with_info
      |> Enum.group_by(& &1.node_id)
      |> Enum.reduce(%{}, fn {node_id, refs}, acc ->
        first = hd(refs)
        repaired_data = repair_node_data(first.node_type, first.node_data, refs)

        if repaired_data != first.node_data do
          Map.put(acc, node_id, repaired_data)
        else
          acc
        end
      end)

    # Apply repairs inside a transaction
    Repo.transaction(fn ->
      Enum.each(repairs_by_node, fn {node_id, new_data} ->
        node = Repo.get!(FlowNode, node_id)
        # Use do_update_node_data path via Flows facade to re-trigger reference tracking
        Storyarn.Flows.update_node_data(node, new_data)
      end)

      map_size(repairs_by_node)
    end)
  end

  @doc """
  Returns a MapSet of node IDs in a flow that have at least one stale reference.
  Uses pure SQL comparison — no JSON scanning in Elixir.
  """
  @spec list_stale_node_ids(integer()) :: MapSet.t()
  def list_stale_node_ids(flow_id) do
    from(vr in VariableReference,
      join: n in FlowNode, on: n.id == vr.flow_node_id,
      join: b in Block, on: b.id == vr.block_id,
      join: p in Page, on: p.id == b.page_id,
      where: n.flow_id == ^flow_id,
      where: is_nil(p.deleted_at),
      where: is_nil(b.deleted_at),
      where: vr.source_page != p.shortcut or vr.source_variable != b.variable_name,
      distinct: true,
      select: n.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # -- Private --

  defp extract_write_refs(node) do
    assignments = node.data["assignments"] || []
    project_id = get_project_id(node.flow_id)

    if project_id do
      Enum.flat_map(assignments, fn assign ->
        write_ref =
          case resolve_block(project_id, assign["page"], assign["variable"]) do
            nil ->
              []

            block_id ->
              [
                %{
                  block_id: block_id,
                  kind: "write",
                  source_page: assign["page"],
                  source_variable: assign["variable"]
                }
              ]
          end

        read_ref =
          if assign["value_type"] == "variable_ref" do
            case resolve_block(project_id, assign["value_page"], assign["value"]) do
              nil ->
                []

              block_id ->
                [
                  %{
                    block_id: block_id,
                    kind: "read",
                    source_page: assign["value_page"],
                    source_variable: assign["value"]
                  }
                ]
            end
          else
            []
          end

        write_ref ++ read_ref
      end)
    else
      []
    end
  end

  defp extract_read_refs(node) do
    rules = get_in(node.data, ["condition", "rules"]) || []
    project_id = get_project_id(node.flow_id)

    if project_id do
      Enum.flat_map(rules, fn rule ->
        case resolve_block(project_id, rule["page"], rule["variable"]) do
          nil ->
            []

          block_id ->
            [
              %{
                block_id: block_id,
                kind: "read",
                source_page: rule["page"],
                source_variable: rule["variable"]
              }
            ]
        end
      end)
    else
      []
    end
  end

  defp get_project_id(flow_id) do
    from(f in Flow, where: f.id == ^flow_id, select: f.project_id)
    |> Repo.one()
  end

  defp resolve_block(project_id, page_shortcut, variable_name)
       when is_binary(page_shortcut) and page_shortcut != "" and
              is_binary(variable_name) and variable_name != "" do
    from(b in Block,
      join: p in Page, on: p.id == b.page_id,
      where: p.project_id == ^project_id,
      where: p.shortcut == ^page_shortcut,
      where: b.variable_name == ^variable_name,
      where: is_nil(p.deleted_at),
      where: is_nil(b.deleted_at),
      select: b.id,
      limit: 1
    )
    |> Repo.one()
  end

  defp resolve_block(_, _, _), do: nil

  # Repairs node data by replacing stale shortcut/variable references with current values.
  # Uses deterministic matching via source_page/source_variable stored in the reference.
  defp repair_node_data("instruction", data, refs) do
    assignments = data["assignments"] || []

    assignments =
      assignments
      |> repair_write_targets(Enum.filter(refs, &(&1.kind == "write")))
      |> repair_read_sources(Enum.filter(refs, &(&1.kind == "read")))

    Map.put(data, "assignments", assignments)
  end

  defp repair_node_data("condition", data, refs) do
    rules = get_in(data, ["condition", "rules"]) || []
    read_refs = Enum.filter(refs, &(&1.kind == "read"))

    updated_rules = repair_condition_rules(rules, read_refs)

    put_in(data, ["condition", "rules"], updated_rules)
  end

  defp repair_node_data(_, data, _refs), do: data

  # Deterministic repair: match each assignment's page+variable to a ref's source_page+source_variable.
  defp repair_write_targets(assignments, write_refs) do
    Enum.map(assignments, fn assignment ->
      matching_ref =
        Enum.find(write_refs, fn ref ->
          ref.source_page == assignment["page"] and
            ref.source_variable == assignment["variable"]
        end)

      if matching_ref do
        assignment
        |> Map.put("page", matching_ref.current_shortcut)
        |> Map.put("variable", matching_ref.current_variable)
      else
        assignment
      end
    end)
  end

  # Deterministic repair for variable_ref read sources in instruction assignments.
  defp repair_read_sources(assignments, read_refs) do
    Enum.map(assignments, fn assignment ->
      if assignment["value_type"] != "variable_ref" do
        assignment
      else
        matching_ref =
          Enum.find(read_refs, fn ref ->
            ref.source_page == assignment["value_page"] and
              ref.source_variable == assignment["value"]
          end)

        if matching_ref do
          assignment
          |> Map.put("value_page", matching_ref.current_shortcut)
          |> Map.put("value", matching_ref.current_variable)
        else
          assignment
        end
      end
    end)
  end

  # Deterministic repair for condition rules.
  defp repair_condition_rules(rules, read_refs) do
    Enum.map(rules, fn rule ->
      matching_ref =
        Enum.find(read_refs, fn ref ->
          ref.source_page == rule["page"] and
            ref.source_variable == rule["variable"]
        end)

      if matching_ref do
        rule
        |> Map.put("page", matching_ref.current_shortcut)
        |> Map.put("variable", matching_ref.current_variable)
      else
        rule
      end
    end)
  end

  defp replace_references(node_id, refs) do
    Repo.transaction(fn ->
      from(vr in VariableReference, where: vr.flow_node_id == ^node_id)
      |> Repo.delete_all()

      unique_refs = Enum.uniq_by(refs, fn r -> {r.block_id, r.kind} end)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(unique_refs, fn ref ->
          %{
            flow_node_id: node_id,
            block_id: ref.block_id,
            kind: ref.kind,
            source_page: ref.source_page,
            source_variable: ref.source_variable,
            inserted_at: now,
            updated_at: now
          }
        end)

      if entries != [] do
        Repo.insert_all(VariableReference, entries, on_conflict: :nothing)
      end
    end)

    :ok
  end

end
