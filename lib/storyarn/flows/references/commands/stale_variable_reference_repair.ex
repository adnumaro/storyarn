defmodule Storyarn.Flows.References.Commands.StaleVariableReferenceRepair do
  @moduledoc """
  Repairs stale Sheet variable identities stored in Flow node data.

  Candidate discovery is read-only. Each candidate is then repaired in its own
  transaction so one damaged node cannot roll back successful repairs in other
  Flows. The transformation is recomputed from the latest locked node and the
  current reference projection, preventing a concurrent editor change from
  being overwritten by JSON captured during discovery.
  """

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Localization
  alias Storyarn.Flows.References
  alias Storyarn.Flows.References.Commands.OwnerAuthority
  alias Storyarn.Flows.References.Queries.StaleVariableReferenceRepair, as: RepairQuery
  alias Storyarn.Flows.References.Rules.StaleVariableReferenceData, as: RepairData
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @max_postgres_bigint 9_223_372_036_854_775_807
  @derivatives_fingerprint_version 1

  @type failure :: {pos_integer(), term()}
  @type partial_error ::
          {:partial_variable_reference_repair,
           %{required(:repaired_count) => non_neg_integer(), required(:failures) => [failure()]}}
  @type error :: :not_found | :unauthorized | :ownership_invariant_violation | partial_error()

  defguardp valid_project_id(project_id)
            when is_integer(project_id) and project_id > 0 and
                   project_id <= @max_postgres_bigint

  @spec repair_project(map(), term()) :: {:ok, non_neg_integer()} | {:error, error()}
  def repair_project(%{user: %{id: actor_id}} = scope, project_id)
      when is_integer(actor_id) and actor_id > 0 and valid_project_id(project_id) do
    with :ok <- authorize_project_owner(scope, project_id) do
      project_id
      |> candidate_repairs()
      |> apply_repairs(scope, project_id)
      |> broadcast_repair_result(project_id)
    end
  end

  def repair_project(%{user: %{id: actor_id}}, _project_id) when is_integer(actor_id) and actor_id > 0,
    do: {:error, :not_found}

  def repair_project(_scope, _project_id), do: {:error, :unauthorized}

  defp authorize_project_owner(scope, project_id) do
    result =
      Repo.transact(fn ->
        with {:ok, project} <- References.lock_active_project(project_id, :update),
             :ok <- OwnerAuthority.authorize_locked(scope, project) do
          {:ok, :authorized}
        else
          {:error, reason} -> {:error, normalize_project_error(reason)}
        end
      end)

    case result do
      {:ok, :authorized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp candidate_repairs(project_id) do
    project_id
    |> RepairQuery.list_with_current_targets()
    |> normalize_references()
    |> Enum.group_by(& &1.node_id)
    |> Enum.reduce([], fn {node_id, references}, candidates ->
      first = hd(references)
      repaired_data = RepairData.repair(first.node_type, first.node_data, references)

      if repaired_data == first.node_data,
        do: candidates,
        else: [{node_id, references} | candidates]
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp apply_repairs(repairs, scope, project_id) do
    {repaired_count, failures} =
      Enum.reduce(repairs, {0, []}, fn repair, acc ->
        collect_repair_result(repair, scope, project_id, acc)
      end)

    aggregate_repair_result(repaired_count, Enum.reverse(failures))
  end

  defp collect_repair_result({node_id, discovery_references}, scope, project_id, {repaired_count, failures}) do
    case repair_single_node(scope, project_id, node_id, discovery_references) do
      {:ok, _node} -> {repaired_count + 1, failures}
      :skip -> {repaired_count, failures}
      {:error, reason} -> {repaired_count, [{node_id, reason} | failures]}
    end
  end

  # Preserve the established hard-delete race contract: a candidate that no
  # longer exists is skipped, while a soft-deleted or otherwise inactive node
  # remains a visible partial failure.
  defp repair_single_node(scope, project_id, node_id, discovery_references) do
    case Repo.get(FlowNode, node_id) do
      nil ->
        :skip

      %FlowNode{} ->
        run_repair_transaction(scope, project_id, node_id, discovery_references)
    end
  end

  defp run_repair_transaction(scope, project_id, node_id, discovery_references) do
    case Repo.transaction(fn ->
           repair_single_node_transaction(scope, project_id, node_id, discovery_references)
         end) do
      {:ok, result} -> result
      {:error, :node_not_found} -> classify_missing_node_after_lock(node_id)
      {:error, reason} -> {:error, reason}
    end
  end

  # A hard delete may land after candidate discovery (or after the optimistic
  # existence check above) but before the node lock is acquired. That race is
  # equivalent to discovering no candidate and remains a no-op. A soft-deleted
  # row is still present and intentionally stays visible as a partial failure.
  defp classify_missing_node_after_lock(node_id) do
    case Repo.get(FlowNode, node_id) do
      nil -> :skip
      %FlowNode{} -> {:error, :node_not_found}
    end
  end

  defp repair_single_node_transaction(scope, project_id, node_id, discovery_references) do
    # Acquire and authorize the Project before Flow and node locks. A mounted
    # owner can lose authority while this maintenance command is running; each
    # independently committed node must therefore reauthorize under the same
    # Project lock that serializes ownership transfer.
    with {:ok, project} <- References.lock_active_project(project_id, :update),
         :ok <- OwnerAuthority.authorize_locked(scope, project),
         {:ok, %{project_id: locked_project_id, flow: flow, node: node}} <-
           References.lock_active_node_for_write(node_id, :update),
         :ok <- ensure_project(locked_project_id, project_id),
         {:ok, _parent_id} <- References.lock_node_parent(flow.id, node.parent_id, node.id) do
      current_references =
        project_id
        |> RepairQuery.list_node_with_current_targets(node_id)
        |> normalize_references()

      references =
        merge_revalidated_discovery_references(
          project_id,
          current_references,
          discovery_references
        )

      repaired_data = RepairData.repair(node.type, node.data, references)
      persist_repair(node, repaired_data, project_id)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_project(project_id, project_id), do: :ok
  defp ensure_project(_locked_project_id, _requested_project_id), do: {:error, :node_not_found}

  defp persist_repair(%FlowNode{data: data}, data, _project_id), do: :skip

  defp persist_repair(%FlowNode{} = node, data, project_id) do
    node
    |> Ecto.Changeset.change(%{
      data: data,
      word_count: Localization.node_word_count(node.type, data),
      derivatives_fingerprint: derivatives_fingerprint(node.type, data)
    })
    |> Repo.update()
    |> refresh_derivatives(project_id)
  end

  defp refresh_derivatives({:ok, node}, project_id) do
    with :ok <- normalize_projection_result(References.update_entity_references(node, project_id: project_id)),
         :ok <- normalize_projection_result(References.update_variable_references(node)),
         :ok <- Localization.extract_flow_node(node) do
      {:ok, node}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp refresh_derivatives({:error, changeset}, _project_id), do: Repo.rollback(changeset)

  defp normalize_projection_result(:ok), do: :ok
  defp normalize_projection_result({:error, reason}), do: {:error, reason}

  defp normalize_projection_result(result), do: {:error, {:unexpected_reference_write_result, result}}

  defp aggregate_repair_result(repaired_count, []) do
    {:ok, repaired_count}
  end

  defp aggregate_repair_result(0, failures) do
    case failures |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
      [:unauthorized] -> {:error, :unauthorized}
      [:ownership_invariant_violation] -> {:error, :ownership_invariant_violation}
      _mixed_failures -> partial_repair_error(0, failures)
    end
  end

  defp aggregate_repair_result(repaired_count, failures), do: partial_repair_error(repaired_count, failures)

  defp partial_repair_error(repaired_count, failures) do
    {:error, {:partial_variable_reference_repair, %{repaired_count: repaired_count, failures: failures}}}
  end

  defp normalize_project_error(reason) when reason in [:project_not_found, :project_not_active], do: :not_found
  defp normalize_project_error(reason), do: reason

  defp normalize_references(references), do: Enum.map(references, &RepairData.normalize_reference/1)

  # Revalidate discovery evidence in case another maintenance path changed the
  # projection after candidate discovery. Preserve only evidence whose target
  # block is still active under the Project lock. A current row for the same
  # authored identity always wins, so a concurrent change that now resolves to
  # another block is never overwritten.
  defp merge_revalidated_discovery_references(project_id, current_references, discovery_references) do
    current_identities = MapSet.new(current_references, &reference_identity/1)

    current_targets =
      discovery_references
      |> Enum.map(& &1.block_id)
      |> Enum.uniq()
      |> then(&RepairQuery.current_targets(project_id, &1))

    retained_discovery =
      Enum.flat_map(discovery_references, fn reference ->
        retain_discovery_reference(reference, current_identities, current_targets)
      end)

    current_references ++ retained_discovery
  end

  defp retain_discovery_reference(reference, current_identities, current_targets) do
    with false <- MapSet.member?(current_identities, reference_identity(reference)),
         {:ok, target} <- Map.fetch(current_targets, reference.block_id) do
      reference
      |> Map.merge(target)
      |> RepairData.normalize_reference()
      |> List.wrap()
    else
      _current_or_missing_target -> []
    end
  end

  defp reference_identity(reference) do
    {reference.kind, reference.source_sheet, reference.source_variable}
  end

  # Keep this certification local to the reference-repair writer. Importing an
  # editor command here would couple two Flow capabilities solely to share five
  # deterministic lines, while the persisted value must remain byte-for-byte
  # compatible with every ordinary Flow write.
  defp derivatives_fingerprint(type, data) do
    {@derivatives_fingerprint_version, type, data}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp broadcast_repair_result({:ok, count} = result, project_id) when count > 0 do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    result
  end

  defp broadcast_repair_result(
         {:error, {:partial_variable_reference_repair, %{repaired_count: count}}} = result,
         project_id
       )
       when count > 0 do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    result
  end

  defp broadcast_repair_result(result, _project_id), do: result
end
