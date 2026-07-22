defmodule Storyarn.Flows.EntityTrashRefs do
  @moduledoc """
  Generic sweep + restore API for `flows_entity_trash_refs`.

  When a target entity (sheet, asset, flow, flow_node-hub, sheet_avatar)
  is soft-deleted, call the appropriate `sweep_*` function to move all
  live refs to the trash table. On restore, call `restore/2` to re-apply
  the refs conservatively (only if the live field is currently nil —
  i.e., the user hasn't re-pointed it elsewhere in the meantime).

  Source types supported: `flow_node`.
  Target types supported: `:sheet`, `:asset`, `:flow`, `:flow_node`,
  `:sheet_avatar`.

  The `:flow_sequence` target type was removed in Phase 1 of the flow
  relational refactor: sequences are now `flow_nodes` with
  `type='sequence'` and their inbound refs are handled by a DB trigger.

  Path kinds supported in v1:
    * Column on the source row — see `sweep_column/5`.
    * Flat JSONB field — see `sweep_jsonb_field/6`.

  Nested JSONB array paths are intentionally not part of the current
  sequence media model; sequence visual/audio records are relational.

  All operations run in `Repo.transaction`.

  ## Cross-domain callers

  External contexts (Sheets, Assets) that hold soft-deletable targets must
  call through the `Storyarn.Flows` facade:

      Flows.sweep_trash_refs_jsonb(FlowNode, "flow_node", :data,
        "speaker_sheet_id", :sheet, sheet.id)
      Flows.restore_trash_refs(:sheet, sheet.id)

  This crosses domain boundaries (flagged by static analysis) but is
  necessary for referential integrity — see
  `project_entity_trash_refs_pattern.md` in user memory for the full
  rationale.
  """

  import Ecto.Query

  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @type target_type ::
          :sheet | :asset | :flow | :flow_node | :sheet_avatar

  @project_restore_sources_locked_event [
    :storyarn,
    :flows,
    :entity_trash_refs,
    :project_restore_sources_locked
  ]

  defguardp valid_project_restore_arguments?(project_id, flow_ids, node_ids)
            when is_integer(project_id) and project_id > 0 and is_list(flow_ids) and
                   is_list(node_ids)

  @target_type_to_column %{
    sheet: :target_sheet_id,
    asset: :target_asset_id,
    flow: :target_flow_id,
    flow_node: :target_flow_node_id,
    sheet_avatar: :target_sheet_avatar_id
  }

  @source_type_to_schema %{
    "flow_node" => FlowNode
  }

  # ===========================================================================
  # Sweep — column
  # ===========================================================================

  @doc """
  Sweep all rows of `source_schema` where `source_column = target_id`.
  Inserts a trash ref per row; sets the column to nil.

  Returns `{:ok, swept_count}`.
  """
  @spec sweep_column(module(), String.t(), atom(), target_type(), integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def sweep_column(source_schema, source_type, source_column, target_type, target_id)
      when is_atom(source_schema) and is_binary(source_type) and is_atom(source_column) and is_integer(target_id) do
    validate_source_type!(source_type)
    target_column = fetch_target_column!(target_type)

    Repo.transaction(fn ->
      rows =
        source_schema
        |> where([s], field(s, ^source_column) == ^target_id)
        |> order_by([s], asc: s.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      case rows do
        [] ->
          0

        _ ->
          source_field = Atom.to_string(source_column)
          insert_trash_refs(rows, source_type, source_field, target_column, target_id)

          {count, _} =
            source_schema
            |> where([s], field(s, ^source_column) == ^target_id)
            |> Repo.update_all(set: [{source_column, nil}])

          count
      end
    end)
  end

  # ===========================================================================
  # Sweep — flat JSONB field
  # ===========================================================================

  @doc """
  Sweep all rows of `source_schema` whose `jsonb_column->>jsonb_key = target_id`.
  Inserts a trash ref per row; sets the key value to nil inside the JSONB
  (key is preserved, value becomes null).

  Returns `{:ok, swept_count}`.

  ## Example

      # On Sheet delete — sweep flow_nodes.data.speaker_sheet_id
      sweep_jsonb_field(FlowNode, "flow_node", :data, "speaker_sheet_id",
        :sheet, sheet.id)
  """
  @spec sweep_jsonb_field(module(), String.t(), atom(), String.t(), target_type(), integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def sweep_jsonb_field(source_schema, source_type, jsonb_column, jsonb_key, target_type, target_id)
      when is_atom(source_schema) and is_binary(source_type) and is_atom(jsonb_column) and is_binary(jsonb_key) and
             is_integer(target_id) do
    validate_source_type!(source_type)
    target_column = fetch_target_column!(target_type)
    target_id_str = Integer.to_string(target_id)

    Repo.transaction(fn ->
      rows =
        source_schema
        |> where(
          [s],
          fragment("?->>? = ?", field(s, ^jsonb_column), ^jsonb_key, ^target_id_str)
        )
        |> order_by([s], asc: s.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      sweep_jsonb_rows(rows, source_schema, source_type, jsonb_column, jsonb_key, target_column, target_id)
    end)
  end

  @doc """
  Sweeps `data.referenced_flow_id` only from nodes whose owning Flow belongs
  to `project_id`.

  Project snapshot restore uses this narrower boundary when it moves a
  current-only Flow to trash. It must never mutate a source row owned by a
  different project, even if corrupt data points at the target Flow.
  """
  @spec sweep_project_flow_references(integer(), integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def sweep_project_flow_references(project_id, target_flow_id)
      when is_integer(project_id) and project_id > 0 and is_integer(target_flow_id) and target_flow_id > 0 do
    target_flow_id_string = Integer.to_string(target_flow_id)

    project_flow_ids =
      from(flow in Flow,
        where: flow.project_id == ^project_id,
        select: flow.id
      )

    Repo.transaction(fn ->
      rows =
        Repo.all(
          from(node in FlowNode,
            where: node.flow_id in subquery(project_flow_ids),
            where:
              fragment("?->>'referenced_flow_id'", node.data) ==
                ^target_flow_id_string,
            order_by: [asc: node.id],
            lock: "FOR UPDATE"
          )
        )

      sweep_jsonb_rows(
        rows,
        FlowNode,
        "flow_node",
        :data,
        "referenced_flow_id",
        :target_flow_id,
        target_flow_id
      )
    end)
  end

  # ===========================================================================
  # Restore
  # ===========================================================================

  @doc """
  Restore all trash refs pointing at `{target_type, target_id}`. Conservative:
  only re-applies a ref if the live source field is currently nil (don't yank
  refs the user created in the interim).

  Always deletes the processed trash rows, whether restored or skipped.

  Returns `{:ok, %{restored: n, skipped: m}}`.
  """
  @spec restore(target_type(), integer()) ::
          {:ok, %{restored: non_neg_integer(), skipped: non_neg_integer()}} | {:error, term()}
  def restore(target_type, target_id) when is_integer(target_id) do
    target_column = fetch_target_column!(target_type)

    Repo.transaction(fn ->
      case lock_restore_target(target_type, target_id) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      refs =
        EntityTrashRef
        |> where([r], field(r, ^target_column) == ^target_id)
        |> order_by([r], asc: r.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      results =
        Enum.map(refs, fn ref ->
          outcome = apply_restore(ref, target_id)
          Repo.delete!(ref)
          outcome
        end)

      %{
        restored: Enum.count(results, &(&1 == :restored)),
        skipped: Enum.count(results, &(&1 == :skipped))
      }
    end)
  end

  @doc """
  Reconciles pending Flow trash references after an exact project restore.

  The project snapshot is authoritative for every source node that it
  materialized, so pending rows for those sources are discarded without
  re-injecting their pre-restore value. Sources outside the target snapshot may
  only be touched when they are still effectively in trash (the node or its
  owning Flow is deleted); their reference is then restored conservatively.

  Foreign-project sources and active same-project sources outside the target
  snapshot fail the whole operation before any source row or trash reference is
  changed.
  """
  @spec reconcile_project_restore_flow_refs(
          integer(),
          [integer()],
          [integer()]
        ) ::
          {:ok,
           %{
             discarded: non_neg_integer(),
             restored: non_neg_integer(),
             skipped: non_neg_integer()
           }}
          | {:error, term()}
  def reconcile_project_restore_flow_refs(project_id, target_flow_ids, target_snapshot_node_ids)
      when valid_project_restore_arguments?(project_id, target_flow_ids, target_snapshot_node_ids) do
    target_flow_ids = normalize_positive_ids(target_flow_ids)
    target_snapshot_node_ids = target_snapshot_node_ids |> normalize_positive_ids() |> MapSet.new()

    Repo.transaction(fn ->
      with :ok <- validate_active_restore_targets(project_id, target_flow_ids),
           refs = lock_project_restore_flow_refs(target_flow_ids),
           :ok <- validate_project_restore_ref_shapes(refs),
           {:ok, source_states} <-
             lock_and_validate_project_restore_sources(
               refs,
               project_id,
               target_snapshot_node_ids
             ) do
        emit_project_restore_sources_locked(project_id, refs, source_states)

        reconcile_project_restore_refs(
          refs,
          source_states,
          target_snapshot_node_ids
        )
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp normalize_positive_ids(ids) do
    ids
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp validate_active_restore_targets(_project_id, []), do: :ok

  defp validate_active_restore_targets(project_id, target_flow_ids) do
    targets =
      Repo.all(
        from(flow in Flow,
          where: flow.id in ^target_flow_ids,
          order_by: [asc: flow.id],
          lock: "FOR UPDATE"
        )
      )

    target_by_id = Map.new(targets, &{&1.id, &1})

    Enum.reduce_while(target_flow_ids, :ok, fn flow_id, :ok ->
      case Map.get(target_by_id, flow_id) do
        %Flow{project_id: ^project_id, deleted_at: nil} ->
          {:cont, :ok}

        %Flow{project_id: ^project_id} ->
          {:halt, {:error, {:project_restore_flow_target_not_active, flow_id}}}

        %Flow{project_id: owner_project_id} ->
          {:halt, {:error, {:project_restore_flow_target_ownership_conflict, flow_id, owner_project_id}}}

        nil ->
          {:halt, {:error, {:project_restore_flow_target_missing, flow_id}}}
      end
    end)
  end

  defp lock_project_restore_flow_refs([]), do: []

  defp lock_project_restore_flow_refs(target_flow_ids) do
    Repo.all(
      from(ref in EntityTrashRef,
        where: ref.target_flow_id in ^target_flow_ids,
        order_by: [asc: ref.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp validate_project_restore_ref_shapes(refs) do
    case Enum.find(
           refs,
           &(&1.source_type != "flow_node" or
               &1.source_field != "data.referenced_flow_id")
         ) do
      nil -> :ok
      ref -> {:error, {:invalid_project_restore_flow_trash_reference, ref.id}}
    end
  end

  defp lock_and_validate_project_restore_sources([], _project_id, _target_snapshot_node_ids), do: {:ok, %{}}

  defp lock_and_validate_project_restore_sources(refs, project_id, target_snapshot_node_ids) do
    source_ids = refs |> Enum.map(& &1.source_id) |> Enum.uniq() |> Enum.sort()

    source_scopes =
      Repo.all(
        from(node in FlowNode,
          join: flow in Flow,
          on: flow.id == node.flow_id,
          where: node.id in ^source_ids,
          order_by: [asc: node.id],
          select: %{node_id: node.id, flow_id: flow.id, project_id: flow.project_id}
        )
      )

    case Enum.find(source_scopes, &(&1.project_id != project_id)) do
      %{node_id: node_id, project_id: owner_project_id} ->
        {:error, {:project_restore_flow_trash_reference_cross_project_source, node_id, owner_project_id}}

      nil ->
        lock_and_validate_same_project_sources(
          source_ids,
          source_scopes,
          project_id,
          target_snapshot_node_ids
        )
    end
  end

  defp lock_and_validate_same_project_sources(source_ids, source_scopes, project_id, target_snapshot_node_ids) do
    flow_ids = source_scopes |> Enum.map(& &1.flow_id) |> Enum.uniq() |> Enum.sort()

    locked_flows =
      Repo.all(
        from(flow in Flow,
          where: flow.id in ^flow_ids and flow.project_id == ^project_id,
          order_by: [asc: flow.id],
          lock: "FOR UPDATE"
        )
      )

    locked_nodes =
      Repo.all(
        from(node in FlowNode,
          where: node.id in ^source_ids,
          order_by: [asc: node.id],
          lock: "FOR UPDATE"
        )
      )

    flow_by_id = Map.new(locked_flows, &{&1.id, &1})

    source_states =
      Map.new(locked_nodes, fn node ->
        {node.id, %{node: node, flow: Map.fetch!(flow_by_id, node.flow_id)}}
      end)

    case Enum.find(source_states, fn {node_id, %{node: node, flow: flow}} ->
           not MapSet.member?(target_snapshot_node_ids, node_id) and
             is_nil(node.deleted_at) and is_nil(flow.deleted_at)
         end) do
      {node_id, _state} ->
        {:error, {:project_restore_flow_trash_reference_unexpected_active_source, node_id}}

      nil ->
        {:ok, source_states}
    end
  end

  defp reconcile_project_restore_refs(refs, source_states, target_snapshot_node_ids) do
    Enum.reduce(
      refs,
      %{discarded: 0, restored: 0, skipped: 0},
      fn ref, counts ->
        outcome =
          cond do
            MapSet.member?(target_snapshot_node_ids, ref.source_id) ->
              :discarded

            source_state = Map.get(source_states, ref.source_id) ->
              apply_project_restore(ref, source_state)

            true ->
              :skipped
          end

        Repo.delete!(ref)
        Map.update!(counts, outcome, &(&1 + 1))
      end
    )
  end

  defp emit_project_restore_sources_locked(project_id, refs, source_states) do
    :telemetry.execute(
      @project_restore_sources_locked_event,
      %{reference_count: length(refs), source_count: map_size(source_states)},
      %{project_id: project_id}
    )
  end

  defp apply_project_restore(
         %EntityTrashRef{
           source_type: "flow_node",
           source_field: "data.referenced_flow_id",
           target_flow_id: target_flow_id
         } = ref,
         %{node: %FlowNode{} = node, flow: %Flow{}}
       ) do
    restore_jsonb_row(
      node,
      ref,
      FlowNode,
      :data,
      "referenced_flow_id",
      target_flow_id
    )
  end

  defp validate_source_type!(source_type) do
    if !Map.has_key?(@source_type_to_schema, source_type) do
      raise ArgumentError, "invalid source_type: #{inspect(source_type)}"
    end
  end

  defp fetch_target_column!(target_type) do
    case Map.fetch(@target_type_to_column, target_type) do
      {:ok, col} -> col
      :error -> raise ArgumentError, "invalid target_type: #{inspect(target_type)}"
    end
  end

  defp lock_restore_target(:sheet_avatar, target_id) do
    AvatarIntegrity.lock_avatar_reference_target(target_id)
  end

  defp lock_restore_target(_target_type, _target_id), do: :ok

  defp insert_trash_refs(rows, source_type, source_field, target_column, target_id) do
    now = TimeHelpers.now()

    entries =
      Enum.map(rows, fn row ->
        Map.put(
          %{source_type: source_type, source_id: row.id, source_field: source_field, inserted_at: now},
          target_column,
          target_id
        )
      end)

    Repo.insert_all(EntityTrashRef, entries)
  end

  defp sweep_jsonb_rows([], _source_schema, _source_type, _jsonb_column, _jsonb_key, _target_column, _target_id) do
    0
  end

  defp sweep_jsonb_rows(rows, source_schema, source_type, jsonb_column, jsonb_key, target_column, target_id) do
    source_field = "#{jsonb_column}.#{jsonb_key}"
    insert_trash_refs(rows, source_type, source_field, target_column, target_id)
    Enum.each(rows, &clear_jsonb_ref(source_schema, &1, jsonb_column, jsonb_key))
    length(rows)
  end

  defp clear_jsonb_ref(source_schema, row, jsonb_column, jsonb_key) do
    new_jsonb = row |> Map.fetch!(jsonb_column) |> Map.put(jsonb_key, nil)

    source_schema
    |> where([s], s.id == ^row.id)
    |> Repo.update_all(set: [{jsonb_column, new_jsonb}])
  end

  defp apply_restore(%EntityTrashRef{} = ref, target_id) do
    source_schema = Map.fetch!(@source_type_to_schema, ref.source_type)

    if String.contains?(ref.source_field, ".") do
      restore_jsonb_field(ref, source_schema, target_id)
    else
      restore_column(ref, source_schema, target_id)
    end
  end

  defp restore_column(%EntityTrashRef{} = ref, source_schema, target_id) do
    column = String.to_existing_atom(ref.source_field)

    source =
      Repo.one(
        from(source in source_schema,
          where: source.id == ^ref.source_id,
          lock: "FOR UPDATE"
        )
      )

    count =
      case source do
        nil ->
          0

        source ->
          if is_nil(Map.fetch!(source, column)) do
            {count, _} =
              source_schema
              |> where([s], s.id == ^ref.source_id and is_nil(field(s, ^column)))
              |> Repo.update_all(set: [{column, target_id}])

            count
          else
            0
          end
      end

    if count > 0, do: :restored, else: :skipped
  end

  defp restore_jsonb_field(%EntityTrashRef{} = ref, source_schema, target_id) do
    [jsonb_col_str, jsonb_key] = String.split(ref.source_field, ".", parts: 2)
    jsonb_column = String.to_existing_atom(jsonb_col_str)

    source =
      Repo.one(
        from(source in source_schema,
          where: source.id == ^ref.source_id,
          lock: "FOR UPDATE"
        )
      )

    restore_jsonb_row(source, ref, source_schema, jsonb_column, jsonb_key, target_id)
  end

  defp restore_jsonb_row(source, ref, source_schema, jsonb_column, jsonb_key, target_id) do
    case source do
      nil ->
        :skipped

      row ->
        jsonb_map = Map.fetch!(row, jsonb_column) || %{}

        if Map.get(jsonb_map, jsonb_key) == nil do
          restore_missing_jsonb_value(ref, row, source_schema, jsonb_column, jsonb_key, target_id)
        else
          :skipped
        end
    end
  end

  defp restore_missing_jsonb_value(ref, row, source_schema, jsonb_column, jsonb_key, target_id) do
    new_jsonb =
      row
      |> Map.fetch!(jsonb_column)
      |> Kernel.||(%{})
      |> Map.put(jsonb_key, target_id)

    case validate_restored_jsonb(ref, row, jsonb_column, new_jsonb) do
      {:ok, validated_jsonb} ->
        source_schema
        |> where([s], s.id == ^ref.source_id)
        |> Repo.update_all(set: [{jsonb_column, validated_jsonb}])

        :restored

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp validate_restored_jsonb(
         %EntityTrashRef{target_sheet_avatar_id: avatar_id},
         %FlowNode{} = node,
         :data,
         %{"avatar_id" => avatar_id} = data
       )
       when is_integer(avatar_id) do
    AvatarIntegrity.lock_and_normalize_node_avatar(
      node.flow_id,
      node.type,
      data
    )
  end

  defp validate_restored_jsonb(_ref, _row, _jsonb_column, jsonb), do: {:ok, jsonb}
end
