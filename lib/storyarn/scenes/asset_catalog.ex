defmodule Storyarn.Scenes.AssetCatalog do
  @moduledoc """
  Scenes-owned read model for assets shown by the Scene editor.

  It maps the shared assets table through a local persistence record so Scene
  presentation code never depends on the Assets context or its schemas.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Scenes.Persistence.AssetRecord
  alias Storyarn.Shared.SearchHelpers

  @asset_option_limit 80
  @max_option_limit 100

  @type asset_option :: %{
          id: integer(),
          filename: String.t() | nil,
          content_type: String.t() | nil,
          metadata: map()
        }

  @doc "Returns a bounded page of active assets for a Scene-owned picker."
  @spec asset_options(integer(), String.t(), keyword()) :: {[asset_option()], boolean()}
  def asset_options(project_id, kind, opts \\ [])

  def asset_options(project_id, kind, opts)
      when is_integer(project_id) and kind in ["image", "audio"] and is_list(opts) do
    limit = bounded_limit(Keyword.get(opts, :limit, @asset_option_limit))
    selected_id = parse_id(Keyword.get(opts, :selected_id))
    query = opts |> Keyword.get(:query, "") |> normalize_query()

    candidates = list_asset_records(project_id, kind, query, limit + 1)
    page = Enum.take(candidates, limit)
    has_more = length(candidates) > limit
    selected = selected_id && get_active_asset(project_id, selected_id, kind)

    {maybe_include_selected(page, selected, query), has_more}
  end

  def asset_options(_project_id, _kind, _opts), do: {[], false}

  @doc "Builds the initial asset picker page while retaining every selected asset."
  @spec initial_asset_options(integer(), String.t(), [term()]) :: [asset_option()]
  def initial_asset_options(project_id, kind, selected_ids)
      when is_integer(project_id) and kind in ["image", "audio"] and is_list(selected_ids) do
    selected_ids = selected_ids |> Enum.map(&parse_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {options, _has_more} =
      asset_options(project_id, kind,
        limit: @asset_option_limit,
        selected_id: List.first(selected_ids)
      )

    selected_ids
    |> Enum.drop(1)
    |> Enum.reduce(options, fn id, acc ->
      case get_active_asset(project_id, id, kind) do
        nil -> acc
        asset -> append_unique(acc, asset)
      end
    end)
  end

  def initial_asset_options(_project_id, _kind, _selected_ids), do: []

  defp list_asset_records(project_id, kind, query, limit) do
    content_type = "#{kind}/%"

    base =
      from(asset in AssetRecord,
        where:
          asset.project_id == ^project_id and is_nil(asset.deleted_at) and
            ilike(asset.content_type, ^content_type),
        order_by: [desc: asset.inserted_at, desc: asset.id],
        limit: ^limit,
        select: %{
          id: asset.id,
          filename: asset.filename,
          content_type: asset.content_type,
          metadata: asset.metadata
        }
      )

    if query == "" do
      Repo.all(base, log: false)
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"
      Repo.all(where(base, [asset], ilike(asset.filename, ^search_term)), log: false)
    end
  end

  defp get_active_asset(project_id, asset_id, kind) do
    content_type = "#{kind}/%"

    Repo.one(
      from(asset in AssetRecord,
        where:
          asset.project_id == ^project_id and asset.id == ^asset_id and
            is_nil(asset.deleted_at) and ilike(asset.content_type, ^content_type),
        select: %{
          id: asset.id,
          filename: asset.filename,
          content_type: asset.content_type,
          metadata: asset.metadata
        }
      )
    )
  end

  defp maybe_include_selected(assets, nil, _query), do: assets

  defp maybe_include_selected(assets, selected, query) do
    cond do
      query != "" and not String.contains?(normalize(selected.filename), query) -> assets
      Enum.any?(assets, &(&1.id == selected.id)) -> assets
      true -> [selected | assets]
    end
  end

  defp append_unique(options, option) do
    if Enum.any?(options, &(&1.id == option.id)), do: options, else: options ++ [option]
  end

  defp bounded_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_option_limit)
  defp bounded_limit(_limit), do: @asset_option_limit

  defp normalize_query(query) when is_binary(query), do: query |> String.trim() |> String.downcase()
  defp normalize_query(_query), do: ""

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(_value), do: ""

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp parse_id(_id), do: nil
end
