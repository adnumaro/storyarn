defmodule Storyarn.Versioning.MaterializationHelpers do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  @spec now() :: DateTime.t()
  def now, do: TimeHelpers.now()

  @spec timestamps(DateTime.t()) :: map()
  def timestamps(now), do: %{inserted_at: now, updated_at: now}

  @spec root_shortcut(map(), keyword()) :: String.t() | nil
  def root_shortcut(snapshot, opts) do
    cond do
      Keyword.get(opts, :preserve_shortcut, false) -> snapshot["shortcut"]
      Keyword.get(opts, :reset_shortcut, false) -> nil
      true -> snapshot["shortcut"]
    end
  end

  @spec root_parent_id(keyword()) :: integer() | nil
  def root_parent_id(opts), do: Keyword.get(opts, :parent_id)

  @spec root_position(keyword()) :: integer()
  def root_position(opts), do: Keyword.get(opts, :position, 0)

  @spec preserve_external_refs?(keyword()) :: boolean()
  def preserve_external_refs?(opts), do: Keyword.get(opts, :preserve_external_refs, true)

  @spec asset_resolution_opts(keyword(), atom()) :: keyword()
  def asset_resolution_opts(opts, asset_mode) do
    opts
    |> Keyword.take([
      :asset_copy_tracker,
      :asset_error_mode,
      :asset_materialization_cache,
      :asset_source_keys
    ])
    |> Keyword.put(:asset_mode, asset_mode)
  end

  @doc """
  Runs a builder materialization with a storage compensation tracker when it
  owns asset copies.

  Callers that already coordinate a larger transaction may pass their tracker
  through `:asset_copy_tracker`; in that case the caller remains responsible
  for finalizing it. A builder can only own a tracker outside an existing
  transaction, where its own transaction result is the final commit boundary.
  """
  @spec with_asset_copy_tracker(keyword(), (keyword() -> result)) ::
          result | {:error, term()}
        when result: term()
  def with_asset_copy_tracker(opts, fun) when is_list(opts) and is_function(fun, 1) do
    if Keyword.get(opts, :asset_mode) == :copy do
      with_copy_tracker(opts, fun)
    else
      fun.(opts)
    end
  end

  defp with_copy_tracker(opts, fun) do
    case Keyword.get(opts, :asset_copy_tracker) do
      tracker when is_reference(tracker) ->
        fun.(opts)

      _tracker ->
        if Repo.in_transaction?() do
          {:error, :asset_copy_tracker_required_in_transaction}
        else
          run_with_owned_copy_tracker(opts, fun)
        end
    end
  end

  defp run_with_owned_copy_tracker(opts, fun) do
    tracker = StorageCompensation.new()
    opts = Keyword.put(opts, :asset_copy_tracker, tracker)

    try do
      opts
      |> fun.()
      |> finalize_owned_copy_tracker(tracker)
    rescue
      error ->
        StorageCompensation.cleanup_after_rollback!(tracker)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        StorageCompensation.cleanup_after_rollback!(tracker)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp finalize_owned_copy_tracker(result, tracker) do
    cleanup_result =
      if successful_result?(result) do
        StorageCompensation.cleanup_unretained(tracker)
      else
        StorageCompensation.cleanup_after_rollback(tracker)
      end

    case cleanup_result do
      :ok -> result
      {:error, reason} -> {:error, {:asset_storage_cleanup_failed, result, reason}}
    end
  end

  defp successful_result?(result) when is_tuple(result) and tuple_size(result) > 0 do
    elem(result, 0) == :ok
  end

  defp successful_result?(_result), do: false

  @spec resolve_project_external_ref(
          integer() | nil,
          module(),
          atom(),
          integer(),
          keyword()
        ) :: integer() | nil
  def resolve_project_external_ref(nil, _schema, _map_key, _project_id, _opts), do: nil

  def resolve_project_external_ref(source_id, schema, map_key, project_id, opts) do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "project external references must be resolved inside an explicit database transaction"
    end

    cond do
      remapped_id = resolve_external_id_map(source_id, map_key, opts) ->
        if project_owned_ref?(schema, remapped_id, project_id), do: remapped_id

      not preserve_external_refs?(opts) ->
        nil

      project_owned_ref?(schema, source_id, project_id) ->
        source_id

      true ->
        nil
    end
  end

  @spec insert_one_returning_id(module(), module(), map()) :: {:ok, integer()} | {:error, term()}
  def insert_one_returning_id(repo, schema, attrs) do
    case repo.insert_all(schema, [attrs], returning: [:id]) do
      {1, [%{id: id}]} -> {:ok, id}
      other -> {:error, {:insert_failed, schema, other}}
    end
  end

  @spec insert_all(module(), module(), [map()]) :: :ok | {:error, term()}
  def insert_all(_repo, _schema, []), do: :ok

  def insert_all(repo, schema, entries) do
    case repo.insert_all(schema, entries) do
      {count, _} when count == length(entries) -> :ok
      other -> {:error, {:insert_all_failed, schema, other}}
    end
  end

  @spec root_id_map(map(), integer()) :: %{optional(integer()) => integer()}
  def root_id_map(snapshot, new_id) do
    case Map.get(snapshot, "original_id") do
      nil -> %{}
      old_id -> %{old_id => new_id}
    end
  end

  defp resolve_external_id_map(source_id, map_key, opts) do
    opts
    |> Keyword.get(:external_id_maps, %{})
    |> Map.get(map_key, %{})
    |> Map.get(source_id)
  end

  defp project_owned_ref?(SheetAvatar, source_id, project_id) do
    not is_nil(
      Repo.one(
        from avatar in SheetAvatar,
          join: sheet in Sheet,
          on: sheet.id == avatar.sheet_id,
          where:
            avatar.id == ^source_id and sheet.project_id == ^project_id and
              is_nil(sheet.deleted_at),
          lock: "FOR KEY SHARE",
          select: avatar.id
      )
    )
  end

  defp project_owned_ref?(schema, source_id, project_id) do
    not is_nil(
      Repo.one(
        from record in schema,
          where:
            record.id == ^source_id and record.project_id == ^project_id and
              is_nil(field(record, :deleted_at)),
          lock: "FOR UPDATE",
          select: record.id
      )
    )
  end
end
