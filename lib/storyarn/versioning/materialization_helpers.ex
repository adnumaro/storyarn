defmodule Storyarn.Versioning.MaterializationHelpers do
  @moduledoc false

  import Ecto.Query, warn: false

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
