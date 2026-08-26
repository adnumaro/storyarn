defmodule Storyarn.Flows.EntityReferenceTracker do
  @moduledoc """
  Owns the entity-reference projection produced and consumed by Flow nodes.

  The projection is stored in the shared `entity_references` table, but this
  module deliberately uses only records and invariants owned by `Storyarn.Flows`.
  """

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.ProjectReferenceIntegrity
  alias Storyarn.Flows.References.Data.EntityReferenceRecord
  alias Storyarn.Flows.References.Data.SheetRecord
  alias Storyarn.Flows.RichTextMentions
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @doc "Rebuilds the entity references encoded in a persisted Flow node."
  @spec update_references(map(), keyword()) :: :ok | {:error, term()}
  def update_references(node, opts \\ [])

  def update_references(%{id: node_id, data: data}, opts) when is_integer(node_id) and is_map(data) do
    with :ok <- validate_project_id_option(opts) do
      run_reference_update(fn -> replace_references(node_id, opts) end)
    end
  end

  def update_references(_node, _opts), do: :ok

  @doc false
  @spec references_current_ids([map()]) :: MapSet.t(integer())
  def references_current_ids(nodes) when is_list(nodes) do
    valid_nodes =
      Enum.filter(nodes, fn
        %{id: node_id, data: data} when is_integer(node_id) and is_map(data) -> true
        _node -> false
      end)

    node_ids = Enum.map(valid_nodes, & &1.id)
    actual_by_node = reference_sets(node_ids)

    Enum.reduce(valid_nodes, MapSet.new(), fn node, current_ids ->
      expected = expected_reference_set(node.data)
      actual = Map.get(actual_by_node, node.id, MapSet.new())

      if expected == actual,
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  @doc "Deletes every entity-reference row owned by a Flow node."
  @spec delete_references(integer()) :: {non_neg_integer(), nil}
  def delete_references(node_id) when is_integer(node_id) do
    Repo.delete_all(
      from reference in EntityReferenceRecord,
        where: reference.source_type == "flow_node" and reference.source_id == ^node_id
    )
  end

  @doc "Counts references pointing at a Flow-owned entity target."
  @spec count_backlinks(String.t(), integer()) :: non_neg_integer()
  def count_backlinks(target_type, target_id) when target_type in ["sheet", "flow"] and is_integer(target_id) do
    Repo.one(
      from reference in EntityReferenceRecord,
        where:
          reference.target_type == ^target_type and
            reference.target_id == ^target_id,
        select: count(reference.id)
    )
  end

  defp reference_sets([]), do: %{}

  defp reference_sets(node_ids) do
    from(reference in EntityReferenceRecord,
      where:
        reference.source_type == "flow_node" and
          reference.source_id in ^node_ids,
      select: {
        reference.source_id,
        reference.target_type,
        reference.target_id,
        reference.context
      }
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {source_id, target_type, target_id, context}, references ->
      reference = {target_type, target_id, context}
      Map.update(references, source_id, MapSet.new([reference]), &MapSet.put(&1, reference))
    end)
  end

  defp expected_reference_set(data) do
    data
    |> extract_references()
    |> Enum.map(fn reference ->
      {reference.type, parse_id(reference.id), reference.context}
    end)
    |> Enum.reject(fn {_type, target_id, _context} -> is_nil(target_id) end)
    |> MapSet.new()
  end

  defp validate_project_id_option(opts) do
    case Keyword.fetch(opts, :project_id) do
      :error -> :ok
      {:ok, project_id} when is_integer(project_id) and project_id > 0 -> :ok
      {:ok, project_id} -> {:error, {:invalid_project_id, project_id}}
    end
  end

  defp replace_references(node_id, opts) do
    requested_project_id = Keyword.get(opts, :project_id)

    with {:ok, {%FlowNode{data: data}, project_id}} <-
           resolve_node_project(node_id, requested_project_id) do
      delete_references(node_id)

      data
      |> extract_references()
      |> insert_references(node_id, project_id)
    end
  end

  defp resolve_node_project(node_id, requested_project_id) do
    identity =
      Repo.one(
        from node in FlowNode,
          join: flow in Flow,
          on: flow.id == node.flow_id,
          where: node.id == ^node_id,
          select: {node.flow_id, flow.project_id}
      )

    case identity do
      {flow_id, project_id}
      when is_nil(requested_project_id) or project_id == requested_project_id ->
        lock_active_node(node_id, flow_id, project_id, requested_project_id)

      _missing_or_mismatched ->
        project_mismatch(node_id, requested_project_id)
    end
  end

  defp lock_active_node(node_id, flow_id, project_id, requested_project_id) do
    with {:ok, _project} <- ProjectReferenceIntegrity.lock_active_project(project_id),
         %Flow{} <-
           Repo.one(
             from flow in Flow,
               where:
                 flow.id == ^flow_id and flow.project_id == ^project_id and
                   is_nil(flow.deleted_at),
               lock: "FOR SHARE"
           ),
         %FlowNode{} = node <-
           Repo.one(
             from current_node in FlowNode,
               where:
                 current_node.id == ^node_id and current_node.flow_id == ^flow_id and
                   is_nil(current_node.deleted_at),
               lock: "FOR SHARE"
           ) do
      {:ok, {node, project_id}}
    else
      _inactive_or_missing -> project_mismatch(node_id, requested_project_id)
    end
  end

  defp project_mismatch(node_id, requested_project_id),
    do: {:error, {:flow_node_project_mismatch, node_id, requested_project_id}}

  defp insert_references(references, node_id, project_id) do
    now = DateTime.to_naive(TimeHelpers.now())

    entries =
      references
      |> Enum.map(fn reference ->
        reference.id
        |> parse_id()
        |> then(&{&1, reference})
      end)
      |> Enum.reject(fn {target_id, _reference} -> is_nil(target_id) end)
      |> Enum.map(fn {target_id, reference} ->
        %{
          source_type: "flow_node",
          source_id: node_id,
          target_type: reference.type,
          target_id: target_id,
          context: reference.context,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> filter_project_targets(project_id)

    if entries != [] do
      Repo.insert_all(EntityReferenceRecord, entries, on_conflict: :nothing)
    end

    :ok
  end

  defp filter_project_targets(entries, project_id) when is_integer(project_id) do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "project-scoped Flow entity references must be rebuilt inside an explicit database transaction"
    end

    allowed_targets =
      Enum.reduce([{"sheet", SheetRecord}, {"flow", Flow}], MapSet.new(), fn {target_type, schema}, allowed ->
        target_ids =
          entries
          |> Enum.filter(&(&1.target_type == target_type))
          |> Enum.map(& &1.target_id)
          |> Enum.uniq()

        active_ids =
          if target_ids == [] do
            []
          else
            Repo.all(
              from target in schema,
                where:
                  target.id in ^target_ids and target.project_id == ^project_id and
                    is_nil(target.deleted_at),
                order_by: [asc: target.id],
                lock: "FOR SHARE",
                select: target.id
            )
          end

        Enum.reduce(active_ids, allowed, &MapSet.put(&2, {target_type, &1}))
      end)

    Enum.filter(entries, &MapSet.member?(allowed_targets, {&1.target_type, &1.target_id}))
  end

  defp run_reference_update(operation) do
    if Repo.in_transaction?() do
      operation.()
    else
      run_reference_update_transaction(operation)
    end
  end

  defp run_reference_update_transaction(operation) do
    case Repo.transaction(fn -> execute_reference_update!(operation) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_reference_update!(operation) do
    case operation.() do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp extract_references(data) do
    []
    |> maybe_add_sheet_reference(data["speaker_sheet_id"], "speaker")
    |> maybe_add_sheet_reference(data["location_sheet_id"], "location")
    |> then(fn direct_references ->
      mention_references =
        data
        |> RichTextMentions.html_candidates()
        |> Enum.flat_map(&extract_mentions/1)
        |> Enum.map(&Map.put(&1, :context, "dialogue"))

      mention_references ++ direct_references
    end)
  end

  defp extract_mentions(content) when is_binary(content) do
    case RichTextMentions.extract_from_html(content) do
      {:ok, mentions} -> mentions
      {:error, _reason} -> []
    end
  end

  defp extract_mentions(_content), do: []

  defp maybe_add_sheet_reference(references, value, _context) when value in [nil, ""], do: references

  defp maybe_add_sheet_reference(references, sheet_id, context),
    do: [%{type: "sheet", id: sheet_id, context: context} | references]

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  defp parse_id(_id), do: nil
end
