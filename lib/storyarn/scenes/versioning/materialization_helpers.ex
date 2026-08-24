defmodule Storyarn.Scenes.Versioning.MaterializationHelpers do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.AssetCommands
  alias Storyarn.Scenes.Persistence.SheetAvatarRecord
  alias Storyarn.Scenes.Persistence.SheetRecord

  def now, do: TimeHelpers.now()
  def timestamps(now), do: %{inserted_at: now, updated_at: now}

  def root_shortcut(snapshot, opts) do
    cond do
      Keyword.get(opts, :preserve_shortcut, false) -> snapshot["shortcut"]
      Keyword.get(opts, :reset_shortcut, false) -> nil
      true -> snapshot["shortcut"]
    end
  end

  def root_parent_id(opts), do: Keyword.get(opts, :parent_id)
  def root_position(opts), do: Keyword.get(opts, :position, 0)
  def exact_materialization?(opts), do: Keyword.get(opts, :materialization_mode, :portable) == :exact
  def preserve_external_refs?(opts), do: Keyword.get(opts, :preserve_external_refs, true)

  def with_project_storage_lock(project_id, fun) when is_integer(project_id) and project_id > 0 and is_function(fun, 0) do
    AssetCommands.with_project_storage_lock(project_id, fun)
  end

  def with_project_storage_lock(_project_id, _fun), do: {:error, :project_not_found}

  def asset_resolution_opts(opts, asset_mode, project_id) do
    opts
    |> Keyword.take([
      :asset_copy_tracker,
      :asset_materialization_cache,
      :asset_source_keys,
      :pre_materialized_assets,
      :materialization_mode
    ])
    |> Keyword.put(:asset_mode, asset_mode)
    |> maybe_pin_entity_restore_source(opts, project_id)
  end

  defp maybe_pin_entity_restore_source(resolution_opts, opts, project_id) do
    case Keyword.get(opts, :restore_action) do
      {:entity_version_restore, _entity_type} ->
        Keyword.put(resolution_opts, :source_project_id, project_id)

      _materialization_action ->
        resolution_opts
    end
  end

  def with_asset_copy_tracker(opts, fun) when is_list(opts) and is_function(fun, 1) do
    AssetCommands.with_asset_copy_tracker(opts, fun)
  end

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

  def insert_one_returning_id(repo, schema, attrs) do
    case repo.insert_all(schema, [attrs], returning: [:id]) do
      {1, [%{id: id}]} -> {:ok, id}
      other -> {:error, {:insert_failed, schema, other}}
    end
  end

  def insert_all(_repo, _schema, []), do: :ok

  def insert_all(repo, schema, entries) do
    case repo.insert_all(schema, entries) do
      {count, _} when count == length(entries) -> :ok
      other -> {:error, {:insert_all_failed, schema, other}}
    end
  end

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

  defp project_owned_ref?(SheetAvatarRecord, source_id, project_id) do
    not is_nil(
      Repo.one(
        from avatar in SheetAvatarRecord,
          join: sheet in SheetRecord,
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
