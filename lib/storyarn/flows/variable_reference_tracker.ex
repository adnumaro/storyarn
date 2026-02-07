defmodule Storyarn.Flows.VariableReferenceTracker do
  @moduledoc """
  Tracks which flow nodes read/write which variables (blocks).

  Called after every node data save. Extracts variable references from
  the node's structured data (condition rules -> reads, instruction
  assignments -> writes) and upserts them into the variable_references table.
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

  # -- Private --

  defp extract_write_refs(node) do
    assignments = node.data["assignments"] || []
    project_id = get_project_id(node.flow_id)

    if project_id do
      Enum.flat_map(assignments, fn assign ->
        write_ref =
          case resolve_block(project_id, assign["page"], assign["variable"]) do
            nil -> []
            block_id -> [%{block_id: block_id, kind: "write"}]
          end

        read_ref =
          if assign["value_type"] == "variable_ref" do
            case resolve_block(project_id, assign["value_page"], assign["value"]) do
              nil -> []
              block_id -> [%{block_id: block_id, kind: "read"}]
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
          nil -> []
          block_id -> [%{block_id: block_id, kind: "read"}]
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
