defmodule Storyarn.Sheets.Assets.Queries.Catalog do
  @moduledoc """
  Sheet-owned read projection over the shared assets table.

  Reproduces the shared asset listing pipeline exactly so the Sheet editor's
  asset reads cannot drift when the shared implementation changes.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets.Assets.Data.AssetRecord

  @doc "Lists a project's active assets. Opts: :content_type prefix, :search, :limit, :offset."
  def list_assets(project_id, opts \\ []) do
    project_id
    |> list_query(opts)
    |> Repo.all()
  end

  @doc "Gets one active asset by project-scoped identity."
  def get_asset(project_id, asset_id) do
    AssetRecord
    |> where([asset], asset.project_id == ^project_id and asset.id == ^asset_id and is_nil(asset.deleted_at))
    |> Repo.one()
  end

  defp list_query(project_id, opts) do
    from(asset in AssetRecord, where: asset.project_id == ^project_id and is_nil(asset.deleted_at))
    |> apply_content_type_filter(opts)
    |> apply_search_filter(opts)
    |> apply_pagination(opts)
    |> order_by([asset], desc: asset.inserted_at, desc: asset.id)
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
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)
end
