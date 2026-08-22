defmodule Storyarn.Projects.FlowEntityTrashReferences do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.FlowEntityTrashReferenceRecord
  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @source_type "flow_node"
  @source_field "data.referenced_flow_id"

  @doc false
  @spec restore_locked_flow_refs(
          [FlowEntityTrashReferenceRecord.t()],
          [FlowNodeRecord.t()],
          pos_integer()
        ) ::
          {:ok, %{restored: non_neg_integer(), skipped: non_neg_integer()}}
          | {:error, term()}
  def restore_locked_flow_refs(refs, source_nodes, target_flow_id)
      when is_list(refs) and is_list(source_nodes) and is_integer(target_flow_id) and target_flow_id > 0 do
    if Repo.in_transaction?() do
      do_restore_locked_flow_refs(refs, source_nodes, target_flow_id)
    else
      {:error, :locked_flow_trash_restore_requires_transaction}
    end
  end

  def restore_locked_flow_refs(_refs, _source_nodes, _target_flow_id),
    do: {:error, :invalid_locked_flow_trash_restore_arguments}

  @doc """
  Lists the same-project Flows whose subflow nodes currently reference the
  target. The caller captures this before sweeping so the replacement result
  retains the legacy `affected_flow_ids` contract.
  """
  def list_affected_flow_ids(project_id, target_flow_id) do
    target = Integer.to_string(target_flow_id)

    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: node.flow_id == flow.id,
      where: flow.project_id == ^project_id,
      where: node.type == "subflow",
      where: fragment("?->>'referenced_flow_id' = ?", node.data, ^target),
      select: node.flow_id
    )
    |> Repo.all()
    |> Enum.uniq()
  end

  @doc """
  Suspends active same-project references to a root Flow during exact project
  replacement. This deliberately uses the same project scope as the legacy
  writer so corrupt cross-project references are never mutated here.
  """
  def sweep_project_flow_references(project_id, target_flow_id) do
    target = Integer.to_string(target_flow_id)

    active_project_flow_ids =
      from(flow in FlowRecord,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        select: flow.id
      )

    Repo.transaction(fn ->
      rows =
        Repo.all(
          from(node in FlowNodeRecord,
            where: node.flow_id in subquery(active_project_flow_ids),
            where: is_nil(node.deleted_at),
            where: fragment("?->>'referenced_flow_id' = ?", node.data, ^target),
            order_by: [asc: node.id],
            lock: "FOR UPDATE"
          )
        )

      sweep_rows(rows, target_flow_id)
    end)
  end

  @doc """
  Suspends every remaining reference to a descendant Flow. Descendant cascade
  historically applies this unscoped sweep after the descendant is put in
  trash; Project preserves that behavior for exact reconstitution parity.
  """
  def sweep_flow_references(target_flow_id) do
    target = Integer.to_string(target_flow_id)

    Repo.transaction(fn ->
      rows =
        Repo.all(
          from(node in FlowNodeRecord,
            where: fragment("?->>'referenced_flow_id' = ?", node.data, ^target),
            order_by: [asc: node.id],
            lock: "FOR UPDATE"
          )
        )

      sweep_rows(rows, target_flow_id)
    end)
  end

  defp do_restore_locked_flow_refs(refs, source_nodes, target_flow_id) do
    with :ok <- validate_locked_flow_refs(refs, target_flow_id),
         {:ok, source_by_id} <- index_locked_flow_sources(source_nodes) do
      results =
        Enum.map(refs, fn ref ->
          outcome = restore_locked_flow_ref(ref, source_by_id, target_flow_id)
          Repo.delete!(ref)
          outcome
        end)

      {:ok,
       %{
         restored: Enum.count(results, &(&1 == :restored)),
         skipped: Enum.count(results, &(&1 == :skipped))
       }}
    end
  end

  defp validate_locked_flow_refs(refs, target_flow_id) do
    case Enum.find(refs, fn ref ->
           not match?(
             %FlowEntityTrashReferenceRecord{
               source_type: @source_type,
               source_field: @source_field,
               target_flow_id: ^target_flow_id
             },
             ref
           )
         end) do
      nil -> :ok
      ref -> {:error, {:invalid_locked_flow_trash_reference, ref.id}}
    end
  end

  defp index_locked_flow_sources(source_nodes) do
    if Enum.all?(source_nodes, &match?(%FlowNodeRecord{}, &1)) do
      source_by_id = Map.new(source_nodes, &{&1.id, &1})

      if map_size(source_by_id) == length(source_nodes) do
        {:ok, source_by_id}
      else
        {:error, :invalid_locked_flow_trash_sources}
      end
    else
      {:error, :invalid_locked_flow_trash_sources}
    end
  end

  defp restore_locked_flow_ref(ref, source_by_id, target_flow_id) do
    case Map.get(source_by_id, ref.source_id) do
      %FlowNodeRecord{data: data} = node when is_map(data) ->
        if Map.get(data, "referenced_flow_id") == nil do
          restored_data = Map.put(data, "referenced_flow_id", target_flow_id)

          Repo.update_all(
            from(source in FlowNodeRecord, where: source.id == ^node.id),
            set: [data: restored_data]
          )

          :restored
        else
          :skipped
        end

      _missing_or_invalid ->
        :skipped
    end
  end

  defp sweep_rows([], _target_flow_id), do: 0

  defp sweep_rows(rows, target_flow_id) do
    now = TimeHelpers.now()

    entries =
      Enum.map(rows, fn row ->
        %{
          source_type: @source_type,
          source_id: row.id,
          source_field: @source_field,
          target_flow_id: target_flow_id,
          inserted_at: now
        }
      end)

    Repo.insert_all(FlowEntityTrashReferenceRecord, entries)

    Enum.each(rows, fn row ->
      data = Map.put(row.data || %{}, "referenced_flow_id", nil)

      Repo.update_all(
        from(node in FlowNodeRecord, where: node.id == ^row.id),
        set: [data: data]
      )
    end)

    length(rows)
  end
end
