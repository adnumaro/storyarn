defmodule Storyarn.Projects.Assets.Queries.AssetQueries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.StorageKey
  alias Storyarn.Projects.Memberships
  alias Storyarn.Repo

  def list_assets(project_id, opts \\ []) do
    project_id
    |> list_query(opts)
    |> Repo.all()
  end

  def list_asset_ids(project_id, opts \\ []) do
    project_id
    |> list_query(opts)
    |> select([asset], asset.id)
    |> Repo.all()
  end

  def get_asset(asset_id) do
    Repo.one(from(asset in Asset, where: asset.id == ^asset_id and is_nil(asset.deleted_at)))
  end

  def authorize_download(%{user: _} = scope, asset_id) when is_integer(asset_id) and asset_id > 0 do
    with %Asset{} = asset <- get_asset(asset_id),
         true <- project_asset_key?(asset.key, asset.project_id),
         {:ok, _project, _membership} <- Memberships.authorize(scope, asset.project_id, :view) do
      {:ok,
       %{
         project_id: asset.project_id,
         key: asset.key,
         content_type: asset.content_type
       }}
    else
      _missing_or_unauthorized -> {:error, :not_found}
    end
  end

  def authorize_download(_scope, _asset_id), do: {:error, :not_found}

  def get_asset(project_id, asset_id) do
    Repo.one(
      from(asset in Asset,
        where:
          asset.project_id == ^project_id and asset.id == ^asset_id and
            is_nil(asset.deleted_at)
      )
    )
  end

  def get_asset!(project_id, asset_id) do
    Repo.one!(
      from(asset in Asset,
        where:
          asset.project_id == ^project_id and asset.id == ^asset_id and
            is_nil(asset.deleted_at)
      )
    )
  end

  def get_asset_by_key(project_id, key) do
    Repo.one(
      from(asset in Asset,
        where:
          asset.project_id == ^project_id and asset.key == ^key and
            is_nil(asset.deleted_at)
      )
    )
  end

  def get_trashed_asset(project_id, asset_id) do
    Repo.one(
      from(asset in Asset,
        where:
          asset.project_id == ^project_id and asset.id == ^asset_id and
            not is_nil(asset.deleted_at)
      )
    )
  end

  def count_assets_by_type(project_id) do
    from(asset in Asset,
      where: asset.project_id == ^project_id and is_nil(asset.deleted_at),
      group_by: fragment("split_part(?, '/', 1)", asset.content_type),
      select: {fragment("split_part(?, '/', 1)", asset.content_type), count(asset.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def total_storage_size(project_id) do
    Repo.one(
      from(asset in Asset,
        where: asset.project_id == ^project_id and is_nil(asset.deleted_at),
        select: sum(asset.size)
      )
    ) || 0
  end

  def list_assets_for_export(project_id) do
    Repo.all(
      from(asset in Asset,
        where: asset.project_id == ^project_id and is_nil(asset.deleted_at),
        order_by: [asc: asset.inserted_at, asc: asset.id]
      )
    )
  end

  def count_assets(project_id, opts \\ []) do
    project_id
    |> base_query()
    |> apply_content_type_filter(opts)
    |> apply_images_only_filter(opts)
    |> apply_search_filter(opts)
    |> Repo.aggregate(:count)
  end

  def list_image_asset_ids(project_id), do: list_asset_ids(project_id, images_only: true)

  defp list_query(project_id, opts) do
    project_id
    |> base_query()
    |> apply_content_type_filter(opts)
    |> apply_images_only_filter(opts)
    |> apply_search_filter(opts)
    |> apply_pagination(opts)
    |> order_by([asset], desc: asset.inserted_at, desc: asset.id)
  end

  defp base_query(project_id) do
    from(asset in Asset, where: asset.project_id == ^project_id and is_nil(asset.deleted_at))
  end

  defp apply_content_type_filter(query, opts) do
    case Keyword.get(opts, :content_type) do
      nil ->
        query

      prefix ->
        sanitized = SearchHelpers.sanitize_like_query(prefix)
        where(query, [asset], ilike(asset.content_type, ^"#{sanitized}%"))
    end
  end

  defp apply_images_only_filter(query, opts) do
    if Keyword.get(opts, :images_only),
      do: where(query, [asset], ilike(asset.content_type, ^"image/%")),
      else: query
  end

  defp apply_search_filter(query, opts) do
    case Keyword.get(opts, :search) do
      nil ->
        query

      "" ->
        query

      term ->
        escaped = SearchHelpers.sanitize_like_query(term)
        where(query, [asset], ilike(asset.filename, ^"%#{escaped}%"))
    end
  end

  defp apply_pagination(query, opts) do
    query
    |> maybe_limit(Keyword.get(opts, :limit))
    |> maybe_offset(Keyword.get(opts, :offset))
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit_value), do: limit(query, ^limit_value)
  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset_value), do: offset(query, ^offset_value)

  defp project_asset_key?(storage_key, project_id) when is_binary(storage_key) and is_integer(project_id) do
    with true <- StorageKey.canonical?(storage_key),
         ["projects", encoded_project_id, "assets", asset_uuid, filename] <-
           String.split(storage_key, "/", trim: false),
         true <- encoded_project_id == Integer.to_string(project_id),
         {:ok, _uuid} <- Ecto.UUID.cast(asset_uuid),
         true <- filename not in ["", ".", ".."] do
      true
    else
      _invalid_key -> false
    end
  end
end
