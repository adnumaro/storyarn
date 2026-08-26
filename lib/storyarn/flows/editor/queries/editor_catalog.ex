defmodule Storyarn.Flows.EditorCatalog do
  @moduledoc """
  Consumer-owned read model for the Flow editor's foreign catalogs.

  The records in `Storyarn.Flows.Editor.Data` map the shared tables directly.
  This module converts them into the small presentation shape consumed by the
  Flow editor so neither foreign schemas nor storage details cross the Flows
  boundary.
  """

  import Ecto.Query

  alias Storyarn.Flows.Editor.Data.AssetRecord
  alias Storyarn.Flows.Editor.Data.BlockRecord
  alias Storyarn.Flows.Editor.Data.GalleryImageRecord
  alias Storyarn.Flows.Editor.Data.SceneRecord
  alias Storyarn.Flows.Editor.Data.SheetRecord
  alias Storyarn.Flows.Flow
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo

  @mention_limit 20
  @mention_sheet_candidate_limit 20
  @mention_flow_candidate_limit 25
  @speaker_option_limit 100
  @asset_option_limit 80

  @type media_ref :: %{id: integer(), filename: String.t() | nil}
  @type avatar :: %{
          id: integer(),
          name: String.t() | nil,
          position: integer(),
          is_default: boolean(),
          asset: media_ref() | nil
        }
  @type sheet :: %{
          id: integer(),
          name: String.t() | nil,
          color: String.t() | nil,
          banner_asset: media_ref() | nil,
          avatars: [avatar()]
        }
  @type gallery_image :: %{
          id: integer(),
          label: String.t() | nil,
          asset: media_ref() | nil
        }
  @type scene_option :: %{id: integer(), name: String.t() | nil}
  @type mention :: %{
          id: integer(),
          type: String.t(),
          name: String.t() | nil,
          shortcut: String.t() | nil
        }
  @type speaker_option :: %{id: integer(), name: String.t() | nil}
  @type asset_option :: %{
          id: integer(),
          filename: String.t() | nil,
          content_type: String.t() | nil
        }
  @type t :: %{
          sheets: [sheet()],
          gallery_by_sheet: %{optional(integer()) => [gallery_image()]},
          scenes: [scene_option()]
        }

  @doc "Loads every foreign read model needed to start the Flow editor."
  @spec load(integer()) :: t()
  def load(project_id) do
    %{
      sheets: load_sheets(project_id),
      gallery_by_sheet: load_gallery_by_sheet(project_id),
      scenes: load_scenes(project_id)
    }
  end

  @doc "Searches the Sheet and Flow records that can be mentioned from Flow content."
  @spec search_mentions(integer(), String.t()) :: [mention()]
  def search_mentions(project_id, query) when is_integer(project_id) and is_binary(query) do
    query = String.trim(query)

    project_id
    |> mention_candidates(query)
    |> Enum.sort_by(& &1.name)
    |> Enum.take(@mention_limit)
  end

  @doc "Returns a bounded page of Flow-owned speaker options."
  @spec speaker_options(integer(), String.t(), keyword()) :: {[speaker_option()], boolean()}
  def speaker_options(project_id, query, opts \\ []) when is_integer(project_id) and is_binary(query) do
    limit = bounded_option_limit(Keyword.get(opts, :limit, @speaker_option_limit))
    selected_id = parse_id(Keyword.get(opts, :selected_id))
    query = String.trim(query)

    candidates = list_speaker_records(project_id, query, limit + 1)
    page = Enum.take(candidates, limit)
    has_more = length(candidates) > limit
    selected = selected_id && get_active_speaker(project_id, selected_id)

    options =
      page
      |> maybe_include_selected_speaker(selected, query)
      |> Enum.map(&speaker_option/1)

    {options, has_more}
  end

  @doc "Builds the initial speaker picker page while retaining every selected speaker."
  @spec initial_speaker_options(integer(), [term()]) :: [speaker_option()]
  def initial_speaker_options(project_id, selected_ids) when is_list(selected_ids) do
    selected_ids = selected_ids |> Enum.map(&parse_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {options, _has_more} =
      speaker_options(project_id, "",
        limit: @speaker_option_limit,
        selected_id: List.first(selected_ids)
      )

    selected_ids
    |> Enum.drop(1)
    |> Enum.reduce(options, fn id, acc ->
      case get_active_speaker(project_id, id) do
        nil -> acc
        speaker -> append_unique_option(acc, speaker_option(speaker))
      end
    end)
  end

  @doc "Returns a bounded page of active assets for a Flow-owned picker."
  @spec asset_options(integer(), String.t(), keyword()) :: {[asset_option()], boolean()}
  def asset_options(project_id, kind, opts \\ [])

  def asset_options(project_id, kind, opts)
      when is_integer(project_id) and kind in ["image", "audio"] and is_list(opts) do
    limit = bounded_asset_limit(Keyword.get(opts, :limit, @asset_option_limit))
    selected_id = parse_id(Keyword.get(opts, :selected_id))
    query = opts |> Keyword.get(:query, "") |> normalize_query()

    candidates = list_asset_records(project_id, kind, query, limit + 1)
    page = Enum.take(candidates, limit)
    has_more = length(candidates) > limit
    selected = selected_id && get_active_asset(project_id, selected_id, kind)

    options = maybe_include_selected_asset(page, selected, query)
    {options, has_more}
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
        asset -> append_unique_option(acc, asset)
      end
    end)
  end

  def initial_asset_options(_project_id, _kind, _selected_ids), do: []

  @doc "Returns the current speaker name used by the dialogue preview."
  @spec speaker_name(integer(), integer()) :: String.t() | nil
  def speaker_name(project_id, speaker_id) do
    Repo.one(
      from(sheet in SheetRecord,
        where:
          sheet.project_id == ^project_id and sheet.id == ^speaker_id and
            is_nil(sheet.deleted_at),
        select: sheet.name
      )
    )
  end

  defp mention_candidates(project_id, "") do
    sheets =
      Repo.all(
        from(sheet in SheetRecord,
          where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
          order_by: [desc: sheet.updated_at],
          limit: @mention_sheet_candidate_limit,
          select: %{
            type: "sheet",
            id: sheet.id,
            name: sheet.name,
            shortcut: sheet.shortcut
          }
        ),
        log: false
      )

    flows =
      Repo.all(
        from(flow in Flow,
          where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
          order_by: [desc: flow.updated_at],
          limit: @mention_flow_candidate_limit,
          select: %{
            type: "flow",
            id: flow.id,
            name: flow.name,
            shortcut: flow.shortcut
          }
        ),
        log: false
      )

    sheets ++ flows
  end

  defp mention_candidates(project_id, query) do
    search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"

    sheets =
      Repo.all(
        from(sheet in SheetRecord,
          where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
          where: ilike(sheet.name, ^search_term) or ilike(sheet.shortcut, ^search_term),
          order_by: [asc: sheet.name],
          limit: @mention_sheet_candidate_limit,
          select: %{
            type: "sheet",
            id: sheet.id,
            name: sheet.name,
            shortcut: sheet.shortcut
          }
        ),
        log: false
      )

    flows =
      Repo.all(
        from(flow in Flow,
          where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
          where: ilike(flow.name, ^search_term) or ilike(flow.shortcut, ^search_term),
          order_by: [asc: flow.name],
          limit: @mention_flow_candidate_limit,
          select: %{
            type: "flow",
            id: flow.id,
            name: flow.name,
            shortcut: flow.shortcut
          }
        ),
        log: false
      )

    sheets ++ flows
  end

  defp list_speaker_records(project_id, "", limit) do
    Repo.all(
      from(sheet in SheetRecord,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        order_by: [desc: sheet.updated_at],
        limit: ^limit,
        select: %{id: sheet.id, name: sheet.name}
      ),
      log: false
    )
  end

  defp list_speaker_records(project_id, query, limit) do
    search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"

    Repo.all(
      from(sheet in SheetRecord,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where: ilike(sheet.name, ^search_term) or ilike(sheet.shortcut, ^search_term),
        order_by: [asc: sheet.name],
        limit: ^limit,
        select: %{id: sheet.id, name: sheet.name}
      ),
      log: false
    )
  end

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

  defp get_active_speaker(project_id, speaker_id) do
    Repo.one(
      from(sheet in SheetRecord,
        where:
          sheet.project_id == ^project_id and sheet.id == ^speaker_id and
            is_nil(sheet.deleted_at),
        select: %{id: sheet.id, name: sheet.name}
      )
    )
  end

  defp maybe_include_selected_speaker(speakers, nil, _query), do: speakers

  defp maybe_include_selected_speaker(speakers, selected, query) do
    cond do
      query != "" and not String.contains?(normalize(selected.name), normalize(query)) -> speakers
      Enum.any?(speakers, &(&1.id == selected.id)) -> speakers
      true -> [selected | speakers]
    end
  end

  defp maybe_include_selected_asset(assets, nil, _query), do: assets

  defp maybe_include_selected_asset(assets, selected, query) do
    cond do
      query != "" and not String.contains?(normalize(selected.filename), query) -> assets
      Enum.any?(assets, &(&1.id == selected.id)) -> assets
      true -> [selected | assets]
    end
  end

  defp append_unique_option(options, option) do
    if Enum.any?(options, &(&1.id == option.id)), do: options, else: options ++ [option]
  end

  defp speaker_option(speaker), do: %{id: speaker.id, name: speaker.name}

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(_value), do: ""

  defp bounded_option_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @speaker_option_limit)

  defp bounded_option_limit(_limit), do: @speaker_option_limit

  defp bounded_asset_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @asset_option_limit)
  defp bounded_asset_limit(_limit), do: @asset_option_limit

  defp normalize_query(query) when is_binary(query), do: query |> String.trim() |> String.downcase()
  defp normalize_query(_query), do: ""

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp parse_id(_id), do: nil

  defp load_sheets(project_id) do
    from(sheet in SheetRecord,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      order_by: [asc: sheet.position, asc: sheet.name],
      preload: [:banner_asset, avatars: :asset]
    )
    |> Repo.all()
    |> Enum.map(&to_sheet/1)
  end

  defp load_gallery_by_sheet(project_id) do
    from(image in GalleryImageRecord,
      join: block in BlockRecord,
      on: image.block_id == block.id,
      join: sheet in SheetRecord,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and block.type == "gallery" and
          is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
      order_by: [asc: image.position],
      select: {block.sheet_id, image},
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(fn {sheet_id, _image} -> sheet_id end, fn {_sheet_id, image} ->
      to_gallery_image(image)
    end)
  end

  defp load_scenes(project_id) do
    Repo.all(
      from(scene in SceneRecord,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        order_by: [asc: scene.position, asc: scene.name, asc: scene.id],
        select: %{id: scene.id, name: scene.name}
      )
    )
  end

  defp to_sheet(sheet) do
    %{
      id: sheet.id,
      name: sheet.name,
      color: sheet.color,
      banner_asset: media_ref(sheet.banner_asset),
      avatars: Enum.map(sheet.avatars, &to_avatar/1)
    }
  end

  defp to_avatar(avatar) do
    %{
      id: avatar.id,
      name: avatar.name,
      position: avatar.position,
      is_default: avatar.is_default,
      asset: media_ref(avatar.asset)
    }
  end

  defp to_gallery_image(image) do
    %{id: image.id, label: image.label, asset: media_ref(image.asset)}
  end

  defp media_ref(nil), do: nil

  defp media_ref(asset) do
    id =
      case asset.metadata do
        %{"web_asset_id" => web_asset_id} when is_integer(web_asset_id) -> web_asset_id
        _metadata -> asset.id
      end

    %{id: id, filename: asset.filename}
  end
end
