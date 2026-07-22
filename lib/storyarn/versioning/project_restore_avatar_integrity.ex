defmodule Storyarn.Versioning.ProjectRestoreAvatarIntegrity do
  @moduledoc """
  Safely detaches avatar references during an exact project restore.

  A project restore may remove an avatar created after the target snapshot
  while moving its referencing nodes to trash. Detachment is allowed only
  when the mandatory pre-restore snapshot captures the avatar and the exact
  set of referencing nodes. That safety snapshot is then the durable recovery
  path. References held only by pre-existing trash are not captured and make
  the restore fail closed.

  Entity-level restores never use this exception and retain the stricter
  `AvatarIntegrity.ensure_deletable/1` contract.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.SheetAvatar

  @spec detach_recoverable_refs(SheetAvatar.t(), integer(), keyword()) ::
          :ok | {:error, term()}
  def detach_recoverable_refs(%SheetAvatar{} = avatar, project_id, opts) when is_integer(project_id) and is_list(opts) do
    case project_restore_safety_snapshot(opts) do
      {:ok, safety_snapshot} ->
        detach_safety_captured_refs(avatar, project_id, safety_snapshot)

      :disabled ->
        :ok
    end
  end

  defp project_restore_safety_snapshot(opts) do
    if Keyword.get(opts, :full_project_restore, false) and
         Keyword.get(opts, :restore_action) == :project_snapshot_restore do
      case Keyword.get(opts, :pre_restore_snapshot) do
        snapshot when is_map(snapshot) -> {:ok, snapshot}
        _missing -> :disabled
      end
    else
      :disabled
    end
  end

  defp detach_safety_captured_refs(%SheetAvatar{id: avatar_id, sheet_id: sheet_id}, project_id, safety_snapshot) do
    referenced_nodes = lock_referencing_nodes(avatar_id)

    if referenced_nodes == [] do
      :ok
    else
      with {:ok, safety_node_ids} <-
             safety_snapshot_ref_node_ids(
               safety_snapshot,
               sheet_id,
               avatar_id
             ),
           :ok <-
             validate_recoverable_scope(
               referenced_nodes,
               project_id,
               safety_node_ids,
               avatar_id
             ) do
        clear_refs(referenced_nodes, avatar_id)
      end
    end
  end

  defp lock_referencing_nodes(avatar_id) do
    avatar_id_string = Integer.to_string(avatar_id)

    Repo.all(
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: fragment("?->>? = ?", node.data, "avatar_id", ^avatar_id_string),
        order_by: [asc: node.id],
        lock: "FOR UPDATE",
        select: %{id: node.id, project_id: flow.project_id, data: node.data}
      )
    )
  end

  defp safety_snapshot_ref_node_ids(safety_snapshot, sheet_id, avatar_id) do
    with {:ok, sheet_entries} <- snapshot_list(safety_snapshot, "sheets"),
         true <- safety_snapshot_has_avatar?(sheet_entries, sheet_id, avatar_id),
         {:ok, flow_entries} <- snapshot_list(safety_snapshot, "flows"),
         {:ok, node_ids} <- collect_ref_node_ids(flow_entries, avatar_id) do
      {:ok, MapSet.new(node_ids)}
    else
      false ->
        {:error, {:avatar_restore_conflict, avatar_id, :avatar_missing_from_pre_restore_snapshot}}

      {:error, reason} ->
        {:error, {:avatar_restore_conflict, avatar_id, {:invalid_pre_restore_snapshot, reason}}}
    end
  end

  defp snapshot_list(snapshot, key) do
    case Map.get(snapshot, key) do
      entries when is_list(entries) -> {:ok, entries}
      invalid -> {:error, {:invalid_collection, key, invalid}}
    end
  end

  defp safety_snapshot_has_avatar?(sheet_entries, sheet_id, avatar_id) do
    Enum.any?(sheet_entries, fn
      %{"id" => ^sheet_id, "snapshot" => %{"avatars" => avatars}}
      when is_list(avatars) ->
        Enum.any?(avatars, fn
          %{"original_id" => ^avatar_id} -> true
          _avatar -> false
        end)

      _entry ->
        false
    end)
  end

  defp collect_ref_node_ids(flow_entries, avatar_id) do
    Enum.reduce_while(flow_entries, {:ok, []}, fn
      %{"snapshot" => %{"nodes" => nodes}}, {:ok, ids}
      when is_list(nodes) ->
        referenced_ids =
          nodes
          |> Enum.filter(fn
            %{"data" => data} when is_map(data) ->
              normalize_snapshot_id(data["avatar_id"]) == avatar_id

            _node ->
              false
          end)
          |> Enum.map(& &1["original_id"])

        if Enum.all?(referenced_ids, &(is_integer(&1) and &1 > 0)) do
          {:cont, {:ok, referenced_ids ++ ids}}
        else
          {:halt, {:error, :invalid_flow_node_id}}
        end

      invalid, {:ok, _ids} ->
        {:halt, {:error, {:invalid_flow_entry, invalid}}}
    end)
  end

  defp normalize_snapshot_id(id) when is_integer(id) and id > 0, do: id

  defp normalize_snapshot_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> parsed
      _invalid -> nil
    end
  end

  defp normalize_snapshot_id(_id), do: nil

  defp validate_recoverable_scope(referenced_nodes, project_id, safety_node_ids, avatar_id) do
    current_node_ids = MapSet.new(referenced_nodes, & &1.id)

    cond do
      Enum.any?(referenced_nodes, &(&1.project_id != project_id)) ->
        {:error, {:avatar_restore_conflict, avatar_id, :cross_project_node_reference}}

      not MapSet.equal?(current_node_ids, safety_node_ids) ->
        unrecoverable_ids =
          current_node_ids
          |> MapSet.difference(safety_node_ids)
          |> MapSet.to_list()
          |> Enum.sort()

        {:error,
         {:avatar_restore_conflict, avatar_id, {:node_references_missing_from_pre_restore_snapshot, unrecoverable_ids}}}

      true ->
        :ok
    end
  end

  defp clear_refs(referenced_nodes, avatar_id) do
    now = TimeHelpers.now()
    avatar_id_string = Integer.to_string(avatar_id)

    Enum.reduce_while(referenced_nodes, :ok, fn node, :ok ->
      data = Map.put(node.data || %{}, "avatar_id", nil)

      case Repo.update_all(
             from(current in FlowNode,
               where:
                 current.id == ^node.id and
                   fragment(
                     "?->>? = ?",
                     current.data,
                     "avatar_id",
                     ^avatar_id_string
                   )
             ),
             set: [data: data, updated_at: now]
           ) do
        {1, _rows} ->
          {:cont, :ok}

        {count, _rows} ->
          {:halt,
           {:error, {:avatar_restore_conflict, avatar_id, {:avatar_reference_clear_count_mismatch, node.id, count}}}}
      end
    end)
  end
end
