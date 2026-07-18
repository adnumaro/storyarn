defmodule Storyarn.Assets do
  @moduledoc """
  The Assets context.

  Handles file uploads and asset management for projects.
  Supports both local storage (development) and Cloudflare R2 (production).
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Analytics
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.ImageProcessor
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.UploadPolicy
  alias Storyarn.Billing
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Project
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.HtmlSanitizer
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Workspaces.Workspace

  require Logger

  @svg_content_type "image/svg+xml"

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type asset :: Asset.t()
  @type project :: Project.t()
  @type user :: User.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type list_opts :: [
          content_type: String.t(),
          images_only: boolean(),
          search: String.t(),
          limit: non_neg_integer(),
          offset: non_neg_integer()
        ]

  @doc """
  Lists all assets for a project.

  ## Options

    * `:content_type` - Filter by content type prefix (e.g., "image/", "audio/")
    * `:images_only` - Filter to only image assets
    * `:search` - Search by filename
    * `:limit` - Maximum number of assets to return
    * `:offset` - Number of assets to skip

  """
  @spec list_assets(integer(), list_opts()) :: [asset()]
  def list_assets(project_id, opts \\ []) do
    from(a in Asset, where: a.project_id == ^project_id)
    |> apply_content_type_filter(opts)
    |> apply_images_only_filter(opts)
    |> apply_search_filter(opts)
    |> apply_pagination(opts)
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> Repo.all()
  end

  defp apply_content_type_filter(query, opts) do
    case Keyword.get(opts, :content_type) do
      nil ->
        query

      prefix ->
        sanitized = SearchHelpers.sanitize_like_query(prefix)
        where(query, [a], ilike(a.content_type, ^"#{sanitized}%"))
    end
  end

  defp apply_images_only_filter(query, opts) do
    if Keyword.get(opts, :images_only) do
      where(query, [a], ilike(a.content_type, ^"image/%"))
    else
      query
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
        where(query, [a], ilike(a.filename, ^"%#{escaped}%"))
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

  @doc """
  Gets a single asset by ID.

  This lookup does not perform authorization. Callers must authorize access to
  the asset's project before exposing the asset or its storage key.
  """
  @spec get_asset(integer()) :: asset() | nil
  def get_asset(asset_id) do
    Repo.get(Asset, asset_id)
  end

  @doc """
  Gets a single asset by ID within a project.

  Returns `nil` if the asset doesn't exist or doesn't belong to the project.
  """
  @spec get_asset(integer(), integer()) :: asset() | nil
  def get_asset(project_id, asset_id) do
    Asset
    |> where(project_id: ^project_id, id: ^asset_id)
    |> Repo.one()
  end

  @doc """
  Gets a single asset by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_asset!(integer(), integer()) :: asset()
  def get_asset!(project_id, asset_id) do
    Asset
    |> where(project_id: ^project_id, id: ^asset_id)
    |> Repo.one!()
  end

  @doc """
  Gets an asset by its storage key.
  """
  @spec get_asset_by_key(integer(), String.t()) :: asset() | nil
  def get_asset_by_key(project_id, key) do
    Asset
    |> where(project_id: ^project_id, key: ^key)
    |> Repo.one()
  end

  @doc """
  Creates an asset record.

  This only creates the database record. The actual file upload should be
  handled separately using the storage service.
  """
  @spec create_asset(project(), user(), attrs()) :: {:ok, asset()} | {:error, changeset()}
  def create_asset(%Project{} = project, %User{} = user, attrs) do
    project
    |> create_asset_record(user.id, attrs, :generic)
    |> track_asset_created(user, attrs)
  end

  @doc """
  Creates an asset record without a user (for system uploads).
  """
  @spec create_asset(project(), attrs()) :: {:ok, asset()} | {:error, changeset()}
  def create_asset(%Project{} = project, attrs) do
    project
    |> create_asset_record(nil, attrs, :generic)
    |> track_asset_created(nil, attrs)
  end

  @doc """
  Updates an asset's metadata.
  """
  @spec update_asset(asset(), attrs()) :: {:ok, asset()} | {:error, changeset() | term()}
  def update_asset(%Asset{} = asset, attrs) do
    Repo.transaction(fn -> update_asset_in_transaction(asset, attrs) end)
  end

  @doc """
  Deletes an asset and detaches references that do not have database-level
  `ON DELETE` behavior.

  Note: This only deletes database records. The actual files should be deleted
  from storage separately, after this returns `{:ok, asset}`.
  """
  @spec delete_asset(asset()) :: {:ok, asset()} | {:error, changeset() | term()}
  def delete_asset(%Asset{id: asset_id, project_id: project_id}) do
    Repo.transaction(fn ->
      with {:ok, _project} <- lock_active_project_for_asset_write(project_id),
           {:ok, asset} <- lock_asset_for_write(asset_id, project_id) do
        delete_asset_in_transaction(asset)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp delete_asset_in_transaction(asset) do
    detach_asset_metadata_links(asset)

    case detach_sheet_avatar_references(asset) do
      {:ok, sheet_ids} ->
        _updated_flow_nodes = clear_flow_node_audio_references(asset)
        _updated_localized_texts = clear_localized_voiceover_references(asset)
        Enum.each(sheet_ids, &promote_default_avatar/1)
        delete_asset_or_rollback(asset)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp delete_asset_or_rollback(asset) do
    case Repo.delete(asset) do
      {:ok, deleted_asset} -> deleted_asset
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking asset changes.
  """
  @spec change_asset(asset(), attrs()) :: changeset()
  def change_asset(%Asset{} = asset, attrs \\ %{}) do
    Asset.update_changeset(asset, attrs)
  end

  @doc """
  Counts assets by content type prefix for a project.

  Returns a map like:
      %{"image" => 10, "audio" => 5}
  """
  @spec count_assets_by_type(integer()) :: %{String.t() => non_neg_integer()}
  def count_assets_by_type(project_id) do
    from(a in Asset,
      where: a.project_id == ^project_id,
      group_by: fragment("split_part(?, '/', 1)", a.content_type),
      select: {fragment("split_part(?, '/', 1)", a.content_type), count(a.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the total size of all assets for a project in bytes.
  """
  @spec total_storage_size(integer()) :: non_neg_integer()
  def total_storage_size(project_id) do
    Repo.one(from(a in Asset, where: a.project_id == ^project_id, select: sum(a.size))) || 0
  end

  @doc """
  Generates a unique storage key for an asset.

  Format: projects/{project_id}/assets/{uuid}/{filename}
  """
  @spec generate_key(project(), String.t()) :: String.t()
  def generate_key(%Project{} = project, filename) do
    uuid = Ecto.UUID.generate()
    sanitized = sanitize_filename(filename)
    "projects/#{project.id}/assets/#{uuid}/#{sanitized}"
  end

  @doc """
  Generates a thumbnail key from an asset key.

  Format: projects/{project_id}/thumbnails/{uuid}/{filename}
  """
  @spec thumbnail_key(String.t()) :: String.t()
  def thumbnail_key(asset_key) do
    String.replace(asset_key, "/assets/", "/thumbnails/")
  end

  @doc """
  Returns a map of usage references for an asset within its project.

  Checks:
  - Flow nodes with `data->>'audio_asset_id'` matching the asset
  - Sequence visual layers and audio tracks
  - Sheets with avatars or banners referencing the asset
  - Scenes with backgrounds, pin icons, or zone label icons referencing the asset
  - Localized voice-over rows that reference the asset
  - Gallery images that reference the asset

  Content in trash is deliberately included because hard-deleting the asset
  also clears or cascades those references. Usage maps expose `:trashed` (or
  the source deletion timestamps for gallery rows) so callers can distinguish
  inactive content without hiding its data-loss impact.

  Returns:
      %{
        asset_metadata_links: [map()],
        flow_nodes: [map()],
        sequence_visual_layers: [map()],
        sequence_tracks: [map()],
        sheet_avatars: [map()],
        sheet_banners: [map()],
        scene_backgrounds: [map()],
        scene_pin_icons: [map()],
        scene_zone_icons: [map()],
        localized_voiceovers: [map()],
        gallery_images: [map()]
      }
  """
  @spec get_asset_usages(integer(), integer()) :: %{
          asset_metadata_links: [map()],
          flow_nodes: [map()],
          sequence_visual_layers: [map()],
          sequence_tracks: [map()],
          sheet_avatars: [map()],
          sheet_banners: [map()],
          scene_backgrounds: [map()],
          scene_pin_icons: [map()],
          scene_zone_icons: [map()],
          localized_voiceovers: [map()],
          gallery_images: [map()]
        }
  def get_asset_usages(project_id, asset_id) do
    asset_metadata_links = list_asset_metadata_links(project_id, asset_id)
    flow_nodes = list_flow_nodes_using_asset(project_id, asset_id)
    sequence_visual_layers = list_sequence_visual_layers_using_asset(project_id, asset_id)
    sequence_tracks = list_sequence_tracks_using_asset(project_id, asset_id)
    sheet_avatars = list_sheet_avatars_using_asset(project_id, asset_id)
    sheet_banners = list_sheet_banners_using_asset(project_id, asset_id)
    scene_backgrounds = list_scenes_using_asset_as_background(project_id, asset_id)
    scene_pin_icons = list_scene_pins_using_asset_as_icon(project_id, asset_id)
    scene_zone_icons = list_scene_zones_using_asset_as_icon(project_id, asset_id)
    localized_voiceovers = list_localized_voiceovers_using_asset(project_id, asset_id)
    gallery_images = list_gallery_images_using_asset(project_id, asset_id)

    %{
      asset_metadata_links: asset_metadata_links,
      flow_nodes: flow_nodes,
      sequence_visual_layers: sequence_visual_layers,
      sequence_tracks: sequence_tracks,
      sheet_avatars: sheet_avatars,
      sheet_banners: sheet_banners,
      scene_backgrounds: scene_backgrounds,
      scene_pin_icons: scene_pin_icons,
      scene_zone_icons: scene_zone_icons,
      localized_voiceovers: localized_voiceovers,
      gallery_images: gallery_images
    }
  end

  defp lock_active_project_for_asset_write(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp lock_asset_for_write(asset_id, project_id) do
    case Repo.one(
           from(asset in Asset,
             where: asset.id == ^asset_id and asset.project_id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Asset{} = asset -> {:ok, asset}
      nil -> {:error, :asset_not_found}
    end
  end

  defp create_asset_record(%Project{} = project, uploaded_by_id, attrs, upload_kind) do
    Repo.transaction(fn ->
      with {:ok, _project} <- lock_active_project_for_asset_write(project.id),
           changeset =
             asset_create_changeset(
               %Asset{project_id: project.id, uploaded_by_id: uploaded_by_id},
               attrs,
               upload_kind
             ),
           {:ok, asset} <- Repo.insert(changeset) do
        asset
      else
        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp update_asset_in_transaction(asset, attrs) do
    with {:ok, _project} <- lock_active_project_for_asset_write(asset.project_id),
         {:ok, locked_asset} <- lock_asset_for_write(asset.id, asset.project_id),
         {:ok, updated_asset} <-
           locked_asset
           |> Asset.update_changeset(attrs)
           |> Repo.update() do
      updated_asset
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp asset_create_changeset(asset, attrs, :generic), do: Asset.create_changeset(asset, attrs)

  defp asset_create_changeset(asset, attrs, :sanitized_svg), do: Asset.create_sanitized_svg_changeset(asset, attrs)

  defp detach_asset_metadata_links(%Asset{id: asset_id, project_id: project_id}) do
    asset_id_string = to_string(asset_id)

    project_id
    |> list_assets_with_metadata_link(asset_id_string, lock: "FOR UPDATE")
    |> Enum.each(fn linked_asset ->
      metadata = remove_asset_metadata_link(linked_asset.metadata || %{}, asset_id_string)

      if metadata != (linked_asset.metadata || %{}) do
        linked_asset
        |> Asset.update_changeset(%{metadata: metadata})
        |> Repo.update!()
      end
    end)

    :ok
  end

  defp list_asset_metadata_links(project_id, asset_id) do
    asset_id_string = to_string(asset_id)

    project_id
    |> list_assets_with_metadata_link(asset_id_string)
    |> Enum.map(fn asset ->
      %{
        id: asset.id,
        filename: asset.filename,
        relations: asset_metadata_link_relations(asset.metadata || %{}, asset_id_string)
      }
    end)
  end

  defp list_assets_with_metadata_link(project_id, asset_id_string, opts \\ []) do
    query =
      from(asset in Asset,
        where: asset.project_id == ^project_id,
        where:
          fragment("?->>'web_asset_id' = ?", asset.metadata, ^asset_id_string) or
            fragment("?->>'original_asset_id' = ?", asset.metadata, ^asset_id_string) or
            fragment(
              """
              EXISTS (
                SELECT 1
                FROM jsonb_each_text(
                  CASE
                    WHEN jsonb_typeof(?->'variant_asset_ids') = 'object'
                    THEN ?->'variant_asset_ids'
                    ELSE '{}'::jsonb
                  END
                ) AS variant_link
                WHERE variant_link.value = ?
              )
              """,
              asset.metadata,
              asset.metadata,
              ^asset_id_string
            ),
        order_by: [asc: asset.filename, asc: asset.id]
      )

    case Keyword.get(opts, :lock) do
      nil -> Repo.all(query)
      "FOR UPDATE" -> query |> lock("FOR UPDATE") |> Repo.all()
    end
  end

  defp remove_asset_metadata_link(metadata, asset_id_string) do
    metadata
    |> maybe_remove_web_asset_link(asset_id_string)
    |> maybe_remove_original_asset_link(asset_id_string)
    |> remove_profile_variant_links(asset_id_string)
  end

  defp maybe_remove_web_asset_link(metadata, asset_id_string) do
    if metadata_id_matches?(metadata["web_asset_id"], asset_id_string) do
      Map.drop(metadata, ["web_asset_id", "web_url"])
    else
      metadata
    end
  end

  defp maybe_remove_original_asset_link(metadata, asset_id_string) do
    if metadata_id_matches?(metadata["original_asset_id"], asset_id_string) do
      Map.delete(metadata, "original_asset_id")
    else
      metadata
    end
  end

  defp remove_profile_variant_links(metadata, asset_id_string) do
    case metadata["variant_asset_ids"] do
      profiles when is_map(profiles) ->
        profiles =
          Map.reject(profiles, fn {_profile, asset_id} ->
            metadata_id_matches?(asset_id, asset_id_string)
          end)

        if map_size(profiles) == 0 do
          Map.delete(metadata, "variant_asset_ids")
        else
          Map.put(metadata, "variant_asset_ids", profiles)
        end

      _ ->
        metadata
    end
  end

  defp asset_metadata_link_relations(metadata, asset_id_string) do
    []
    |> maybe_add_metadata_relation(
      metadata_id_matches?(metadata["web_asset_id"], asset_id_string),
      "web_variant"
    )
    |> maybe_add_metadata_relation(
      metadata_id_matches?(metadata["original_asset_id"], asset_id_string),
      "original"
    )
    |> maybe_add_metadata_relation(profile_variant_link?(metadata, asset_id_string), "profile_variant")
    |> Enum.reverse()
  end

  defp profile_variant_link?(%{"variant_asset_ids" => profiles}, asset_id_string) when is_map(profiles) do
    Enum.any?(profiles, fn {_profile, asset_id} ->
      metadata_id_matches?(asset_id, asset_id_string)
    end)
  end

  defp profile_variant_link?(_metadata, _asset_id_string), do: false

  defp maybe_add_metadata_relation(relations, true, relation), do: [relation | relations]
  defp maybe_add_metadata_relation(relations, false, _relation), do: relations

  defp metadata_id_matches?(value, asset_id_string) when is_integer(value),
    do: Integer.to_string(value) == asset_id_string

  defp metadata_id_matches?(value, asset_id_string) when is_binary(value), do: value == asset_id_string

  defp metadata_id_matches?(_value, _asset_id_string), do: false

  @doc """
  Returns the total number of usage references for an asset.
  """
  @spec count_asset_usages(integer(), integer()) :: non_neg_integer()
  def count_asset_usages(project_id, asset_id) do
    usages = get_asset_usages(project_id, asset_id)

    usages
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp detach_sheet_avatar_references(%Asset{id: asset_id, project_id: project_id}) do
    avatars =
      Repo.all(
        from(sa in SheetAvatar,
          join: s in Sheet,
          on: sa.sheet_id == s.id,
          where: sa.asset_id == ^asset_id,
          where: s.project_id == ^project_id,
          order_by: [asc: sa.id],
          lock: "FOR UPDATE",
          select: sa
        )
      )

    with :ok <- ensure_avatars_deletable(avatars) do
      avatar_ids = Enum.map(avatars, & &1.id)
      delete_avatar_rows(avatar_ids)
      {:ok, default_avatar_sheet_ids(avatars)}
    end
  end

  defp ensure_avatars_deletable(avatars) do
    Enum.reduce_while(avatars, :ok, fn avatar, :ok ->
      case AvatarIntegrity.ensure_deletable(avatar.id) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_avatar_rows([]), do: :ok

  defp delete_avatar_rows(avatar_ids) do
    Repo.delete_all(from(sa in SheetAvatar, where: sa.id in ^avatar_ids))
    :ok
  end

  defp default_avatar_sheet_ids(avatars) do
    avatars
    |> Enum.filter(& &1.is_default)
    |> Enum.map(& &1.sheet_id)
    |> Enum.uniq()
  end

  defp promote_default_avatar(sheet_id) do
    default_exists? =
      Repo.exists?(from(sa in SheetAvatar, where: sa.sheet_id == ^sheet_id and sa.is_default == true))

    if default_exists? do
      :ok
    else
      case Repo.one(from(sa in SheetAvatar, where: sa.sheet_id == ^sheet_id, order_by: [asc: sa.position], limit: 1)) do
        nil ->
          :ok

        avatar ->
          avatar
          |> Ecto.Changeset.change(is_default: true)
          |> Repo.update!()

          :ok
      end
    end
  end

  defp clear_flow_node_audio_references(%Asset{id: asset_id, project_id: project_id}) do
    asset_id_str = to_string(asset_id)
    now = TimeHelpers.now()

    {count, _} =
      Repo.update_all(
        from(n in FlowNode,
          join: f in Flow,
          on: n.flow_id == f.id,
          where: f.project_id == ^project_id,
          where: fragment("?->>'audio_asset_id' = ?", n.data, ^asset_id_str),
          update: [set: [data: fragment("? - 'audio_asset_id'", n.data), updated_at: ^now]]
        ),
        []
      )

    count
  end

  defp clear_localized_voiceover_references(%Asset{id: asset_id, project_id: project_id}) do
    text_ids =
      Repo.all(
        from(text in LocalizedText,
          where:
            text.project_id == ^project_id and
              text.vo_asset_id == ^asset_id,
          order_by: [asc: text.id],
          lock: "FOR UPDATE",
          select: text.id
        )
      )

    if text_ids == [] do
      0
    else
      now = TimeHelpers.now()

      query =
        from(text in LocalizedText,
          where: text.id in ^text_ids,
          update: [
            set: [
              vo_asset_id: nil,
              vo_status:
                fragment(
                  "CASE WHEN ? THEN 'needed' ELSE 'none' END",
                  text.vo_eligible
                ),
              updated_at: ^now
            ],
            inc: [lock_version: 1]
          ]
        )

      {count, _rows} = Repo.update_all(query, [])

      count
    end
  end

  defp list_flow_nodes_using_asset(project_id, asset_id) do
    asset_id = to_string(asset_id)

    Repo.all(
      from(node in FlowNode,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        where:
          flow.project_id == ^project_id and
            fragment("?->>'audio_asset_id' = ?", node.data, ^asset_id),
        order_by: [asc: flow.name, asc: node.id],
        select: %{
          node_id: node.id,
          node_type: node.type,
          flow_id: flow.id,
          flow_name: flow.name,
          trashed: not is_nil(node.deleted_at) or not is_nil(flow.deleted_at)
        }
      )
    )
  end

  defp list_sequence_visual_layers_using_asset(project_id, asset_id) do
    Repo.all(
      from(layer in SequenceVisualLayer,
        join: node in FlowNode,
        on: layer.flow_node_id == node.id,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        left_join: config in SequenceConfig,
        on: config.flow_node_id == node.id,
        where: flow.project_id == ^project_id and layer.asset_id == ^asset_id,
        order_by: [asc: flow.name, asc: config.name, asc: layer.z_index, asc: layer.id],
        select: %{
          id: layer.id,
          node_id: node.id,
          flow_id: flow.id,
          flow_name: flow.name,
          sequence_name: config.name,
          label: layer.label,
          kind: layer.kind,
          trashed: not is_nil(node.deleted_at) or not is_nil(flow.deleted_at)
        }
      )
    )
  end

  defp list_sequence_tracks_using_asset(project_id, asset_id) do
    Repo.all(
      from(track in SequenceTrack,
        join: node in FlowNode,
        on: track.flow_node_id == node.id,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        left_join: config in SequenceConfig,
        on: config.flow_node_id == node.id,
        where: flow.project_id == ^project_id and track.asset_id == ^asset_id,
        order_by: [asc: flow.name, asc: config.name, asc: track.kind, asc: track.id],
        select: %{
          id: track.id,
          node_id: node.id,
          flow_id: flow.id,
          flow_name: flow.name,
          sequence_name: config.name,
          kind: track.kind,
          trashed: not is_nil(node.deleted_at) or not is_nil(flow.deleted_at)
        }
      )
    )
  end

  defp list_sheet_avatars_using_asset(project_id, asset_id) do
    Repo.all(
      from(sheet in Sheet,
        join: avatar in SheetAvatar,
        on: avatar.sheet_id == sheet.id,
        where: sheet.project_id == ^project_id and avatar.asset_id == ^asset_id,
        distinct: true,
        order_by: [asc: sheet.name, asc: sheet.id],
        select: %{
          id: sheet.id,
          name: sheet.name,
          trashed: not is_nil(sheet.deleted_at)
        }
      )
    )
  end

  defp list_sheet_banners_using_asset(project_id, asset_id) do
    Repo.all(
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id and sheet.banner_asset_id == ^asset_id,
        order_by: [asc: sheet.name, asc: sheet.id],
        select: %{
          id: sheet.id,
          name: sheet.name,
          trashed: not is_nil(sheet.deleted_at)
        }
      )
    )
  end

  defp list_localized_voiceovers_using_asset(project_id, asset_id) do
    Repo.all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and
            text.vo_asset_id == ^asset_id,
        order_by: [asc: text.locale_code, asc: text.id],
        select: %{
          id: text.id,
          locale_code: text.locale_code,
          source_type: text.source_type,
          source_id: text.source_id,
          source_text: text.source_text,
          archived_at: text.archived_at
        }
      )
    )
  end

  defp list_gallery_images_using_asset(project_id, asset_id) do
    Repo.all(
      from(gallery_image in BlockGalleryImage,
        join: block in Block,
        on: block.id == gallery_image.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and
            gallery_image.asset_id == ^asset_id,
        order_by: [asc: sheet.name, asc: block.position, asc: gallery_image.position],
        select: %{
          id: gallery_image.id,
          block_id: block.id,
          sheet_id: sheet.id,
          sheet_name: sheet.name,
          label: gallery_image.label,
          block_deleted_at: block.deleted_at,
          sheet_deleted_at: sheet.deleted_at
        }
      )
    )
  end

  defp list_scenes_using_asset_as_background(project_id, asset_id) do
    Repo.all(
      from(scene in Scene,
        where: scene.project_id == ^project_id and scene.background_asset_id == ^asset_id,
        order_by: [asc: scene.name, asc: scene.id],
        select: %{
          id: scene.id,
          name: scene.name,
          trashed: not is_nil(scene.deleted_at)
        }
      )
    )
  end

  defp list_scene_pins_using_asset_as_icon(project_id, asset_id) do
    Repo.all(
      from(pin in ScenePin,
        join: scene in Scene,
        on: pin.scene_id == scene.id,
        where: scene.project_id == ^project_id and pin.icon_asset_id == ^asset_id,
        order_by: [asc: scene.name, asc: pin.label, asc: pin.id],
        select: %{
          pin_id: pin.id,
          pin_label: pin.label,
          scene_id: scene.id,
          scene_name: scene.name,
          trashed: not is_nil(scene.deleted_at)
        }
      )
    )
  end

  defp list_scene_zones_using_asset_as_icon(project_id, asset_id) do
    Repo.all(
      from(zone in SceneZone,
        join: scene in Scene,
        on: zone.scene_id == scene.id,
        where: scene.project_id == ^project_id and zone.label_icon_asset_id == ^asset_id,
        order_by: [asc: scene.name, asc: zone.name, asc: zone.id],
        select: %{
          zone_id: zone.id,
          zone_name: zone.name,
          scene_id: scene.id,
          scene_name: scene.name,
          trashed: not is_nil(scene.deleted_at)
        }
      )
    )
  end

  @doc """
  Uploads a file from a temporary path and creates the corresponding asset record.

  Used by LiveView's `consume_uploaded_entries/3` to process file uploads directly
  from the parent LiveView.

  Returns `{:ok, asset}` on success or `{:error, reason}` on failure.
  """
  @spec upload_and_create_asset(
          String.t(),
          Phoenix.LiveView.UploadEntry.t(),
          project(),
          user(),
          keyword()
        ) ::
          {:ok, asset()} | {:error, term()}
  def upload_and_create_asset(path, entry, %Project{} = project, %User{} = user, opts \\ []) do
    do_upload_and_create_asset(path, entry, project, user, opts)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp do_upload_and_create_asset(path, entry, project, user, opts) do
    content = File.read!(path)
    metadata = extract_image_metadata(path, entry.client_type)

    attrs = %{filename: entry.client_name, content_type: entry.client_type, metadata: metadata}

    attrs =
      if purpose = Keyword.get(opts, :purpose), do: Map.put(attrs, :purpose, purpose), else: attrs

    upload_binary_and_create_asset(content, attrs, project, user)
  end

  @doc """
  Inspects a future image upload and returns the action needed for its purpose.

  The caller provides client-side metadata plus a SHA-256 source hash. The
  server uses that hash only for lookup; actual uploads still recompute the
  hash from the received binary.
  """
  @spec inspect_upload(project(), map()) :: {:ok, map()} | {:error, term()}
  def inspect_upload(%Project{} = project, attrs) do
    purpose = attrs |> Map.get("purpose", Map.get(attrs, :purpose)) |> UploadPolicy.parse_purpose()

    with {:ok, profile} <- UploadPolicy.profile_for(purpose),
         {:ok, metadata} <- UploadPolicy.normalize_metadata(attrs),
         :ok <- UploadPolicy.validate(profile, metadata) do
      existing_original = get_asset_by_blob_hash(project.id, metadata.source_hash)
      requires_variant? = requires_variant?(purpose, metadata.content_type, image_metadata(metadata))

      existing_variant =
        if requires_variant? do
          get_asset_by_source_profile(project.id, metadata.source_hash, profile.profile)
        end

      {:ok,
       %{
         action: upload_decision_action(existing_original, existing_variant, requires_variant?),
         source_exists: not is_nil(existing_original),
         variant_exists: not is_nil(existing_variant),
         requires_variant: requires_variant?,
         variant_profile: profile.profile,
         target: profile.target,
         asset_id: decision_asset_id(existing_original, existing_variant, requires_variant?)
       }}
    end
  end

  @doc """
  Materializes a purpose-specific asset from an existing source image.

  This is used after `inspect_upload/2` determines that the source hash already
  exists in the project, so the browser does not need to upload the same binary
  again.
  """
  @spec materialize_upload_variant(project(), user() | nil, map()) ::
          {:ok, asset(), map()} | {:error, term()}
  def materialize_upload_variant(%Project{} = project, user, attrs) do
    with_workspace_upload_lock(project, fn _workspace ->
      do_materialize_upload_variant(project, user, attrs)
    end)
  end

  defp do_materialize_upload_variant(project, user, attrs) do
    purpose = attrs |> Map.get("purpose", Map.get(attrs, :purpose)) |> UploadPolicy.parse_purpose()
    source_hash = Map.get(attrs, "hash") || Map.get(attrs, :hash)

    with {:ok, profile} <- UploadPolicy.profile_for(purpose),
         true <- is_binary(source_hash),
         %Asset{} = original <- get_asset_by_blob_hash(project.id, source_hash),
         {:ok, binary_data} <- Storage.download(original.key) do
      materialize_asset_for_purpose(binary_data, original, project, user, purpose, profile)
    else
      false -> {:error, :invalid_hash}
      nil -> {:error, :source_not_found}
      error -> error
    end
  end

  @doc """
  Uploads a source binary and returns the asset that should be attached for
  the requested purpose.

  For avatar, banner, and scene background uploads this keeps the original
  source once and returns a generated/reused placement-specific variant when
  one is required.
  """
  @spec upload_binary_for_purpose(binary(), map(), project(), user() | nil) ::
          {:ok, asset(), map()} | {:error, term()}
  def upload_binary_for_purpose(binary_data, attrs, %Project{} = project, user \\ nil) do
    purpose = attrs |> Map.get(:purpose, Map.get(attrs, "purpose")) |> UploadPolicy.parse_purpose()

    with {:ok, profile} <- UploadPolicy.profile_for(purpose),
         :ok <- validate_binary_upload(binary_data, attrs, profile) do
      with_workspace_upload_lock(project, fn _workspace ->
        ensure_and_materialize_asset(binary_data, attrs, project, user, purpose, profile)
      end)
    end
  end

  defp ensure_and_materialize_asset(binary_data, attrs, project, user, purpose, profile) do
    with {:ok, original} <- ensure_original_asset(binary_data, attrs, project, user) do
      materialize_asset_for_purpose(binary_data, original, project, user, purpose, profile)
    end
  end

  @doc """
  Uploads binary data to storage, persists a content-addressed blob for
  snapshot restoration, and creates the asset record.

  This is the single entry point for all asset creation from raw binary data.
  LiveView file uploads should use `upload_and_create_asset/4` instead.

  ## Attrs

    * `:filename` — original filename (will be sanitized)
    * `:content_type` — MIME type
    * `:metadata` — optional extra metadata map (default `%{}`)

  Returns `{:ok, asset}` or `{:error, reason}`.
  """
  @spec upload_binary_and_create_asset(binary(), map(), project(), user() | nil) ::
          {:ok, asset()} | {:error, term()}
  def upload_binary_and_create_asset(
        binary_data,
        %{filename: filename, content_type: content_type} = attrs,
        %Project{} = project,
        user \\ nil
      ) do
    with_upload_capacity(project, byte_size(binary_data), fn ->
      do_upload_binary_and_create_asset(
        binary_data,
        %{attrs | filename: filename, content_type: content_type},
        project,
        user,
        :generic
      )
    end)
  end

  @doc """
  Sanitizes and uploads an SVG asset from a server-controlled SVG upload flow.

  Generic asset uploads must use `upload_binary_and_create_asset/4`, which
  rejects SVG. This function exists for scene icon uploads, where SVG support is
  intentional and the content must be sanitized before public storage.
  """
  @spec upload_sanitized_svg_and_create_asset(binary(), map(), project(), user() | nil) ::
          {:ok, asset()} | {:error, term()}
  def upload_sanitized_svg_and_create_asset(binary_data, attrs, %Project{} = project, user \\ nil) when is_map(attrs) do
    with content_type when content_type == @svg_content_type <-
           Map.get(attrs, :content_type, Map.get(attrs, "content_type")),
         {:ok, sanitized_svg} <- sanitize_svg_upload(binary_data) do
      attrs =
        attrs
        |> normalize_asset_attrs()
        |> Map.put(:metadata, attrs |> upload_metadata() |> Map.put("sanitized_svg", true))

      with_upload_capacity(project, byte_size(sanitized_svg), fn ->
        do_upload_binary_and_create_asset(sanitized_svg, attrs, project, user, :sanitized_svg)
      end)
    else
      _ -> {:error, :invalid_svg}
    end
  end

  defp do_upload_binary_and_create_asset(
         binary_data,
         %{filename: filename, content_type: content_type} = attrs,
         %Project{} = project,
         user,
         upload_kind
       ) do
    safe_filename = sanitize_filename(filename)
    key = generate_key(project, safe_filename)

    blob_hash = BlobStore.compute_hash(binary_data)

    asset_attrs = %{
      filename: safe_filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key,
      url: Storage.get_url(key),
      metadata: Map.get(attrs, :metadata, %{}),
      blob_hash: blob_hash
    }

    with :ok <- validate_asset_upload_attrs(asset_attrs, upload_kind) do
      ext = BlobStore.ext_from_content_type(content_type)

      case BlobStore.ensure_blob_with_status(project.id, blob_hash, ext, binary_data) do
        {:ok, blob_key, blob_created?} ->
          persist_uploaded_asset(
            %{
              binary_data: binary_data,
              content_type: content_type,
              key: key,
              blob_key: blob_key,
              blob_created?: blob_created?
            },
            asset_attrs,
            attrs,
            project,
            user,
            upload_kind
          )

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp persist_uploaded_asset(upload, asset_attrs, attrs, project, user, upload_kind) do
    case Storage.upload(upload.key, upload.binary_data, upload.content_type) do
      {:ok, url} ->
        case do_create_asset(project, user, %{asset_attrs | url: url}, upload_kind) do
          {:ok, asset} ->
            maybe_schedule_variant(upload.binary_data, asset, project, user, attrs)
            {:ok, asset}

          {:error, changeset} ->
            cleanup_failed_upload(upload.key, upload.blob_key, upload.blob_created?)
            {:error, changeset}
        end

      {:error, reason} ->
        cleanup_new_blob(upload.blob_key, upload.blob_created?)
        {:error, reason}
    end
  end

  defp cleanup_failed_upload(asset_key, blob_key, blob_created?) do
    StorageCompensation.delete_or_enqueue(asset_key)
    cleanup_new_blob(blob_key, blob_created?)
  end

  defp cleanup_new_blob(_blob_key, false), do: :ok
  defp cleanup_new_blob(blob_key, true), do: StorageCompensation.delete_or_enqueue(blob_key)

  defp with_upload_capacity(%Project{} = project, file_size, fun) when is_function(fun, 0) do
    with_workspace_upload_lock(project, fn workspace ->
      capacity_checked_upload(workspace, file_size, fun)
    end)
  end

  defp capacity_checked_upload(workspace, file_size, fun) do
    case Billing.can_upload_asset?(workspace, file_size) do
      :ok -> fun.()
      {:error, _reason, _details} = error -> error
    end
  end

  defp with_workspace_upload_lock(%Project{} = project, fun) when is_function(fun, 1) do
    fn ->
      workspace = Repo.one!(from(w in Workspace, where: w.id == ^project.workspace_id, lock: "FOR UPDATE"))
      fun.(workspace)
    end
    |> Repo.transaction()
    |> case do
      {:ok, success} -> success
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_asset_upload_attrs(attrs, upload_kind) do
    changeset =
      case upload_kind do
        :sanitized_svg -> Asset.create_sanitized_svg_changeset(%Asset{}, attrs)
        :generic -> Asset.create_changeset(%Asset{}, attrs)
      end

    if changeset.valid?, do: :ok, else: {:error, changeset}
  end

  defp sanitize_svg_upload(binary_data) when is_binary(binary_data) do
    with true <- String.valid?(binary_data),
         svg = binary_data |> strip_utf8_bom() |> String.trim(),
         true <- svg_root?(svg),
         sanitized = HtmlSanitizer.sanitize_html(svg),
         true <- svg_root?(sanitized) do
      {:ok, sanitized}
    else
      _ -> {:error, :invalid_svg}
    end
  end

  defp sanitize_svg_upload(_), do: {:error, :invalid_svg}

  defp strip_utf8_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_utf8_bom(binary), do: binary

  defp svg_root?(svg) when is_binary(svg) do
    case Floki.parse_fragment(svg) do
      {:ok, nodes} -> nodes |> Floki.find("svg") |> Enum.any?()
      _ -> false
    end
  end

  defp upload_metadata(attrs) do
    Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})) || %{}
  end

  defp validate_binary_upload(binary_data, attrs, profile) do
    content_type = Map.get(attrs, :content_type) || Map.get(attrs, "content_type")

    UploadPolicy.validate(profile, %{
      content_type: content_type,
      size: byte_size(binary_data)
    })
  end

  defp ensure_original_asset(binary_data, attrs, project, user) do
    source_hash = BlobStore.compute_hash(binary_data)

    case get_asset_by_blob_hash(project.id, source_hash) do
      %Asset{} = asset ->
        {:ok, ensure_original_metadata(asset, binary_data, source_hash)}

      nil ->
        upload_original_asset(binary_data, attrs, project, user, source_hash)
    end
  end

  defp upload_original_asset(binary_data, attrs, project, user, source_hash) do
    metadata =
      binary_data
      |> image_metadata_from_binary()
      |> Map.merge(%{
        "source_blob_hash" => source_hash,
        "variant_profile" => "original"
      })
      |> Map.merge(Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})))

    original_attrs =
      attrs
      |> normalize_asset_attrs()
      |> Map.merge(%{metadata: metadata, skip_variants: true})

    upload_binary_and_create_asset(binary_data, original_attrs, project, user)
  end

  defp normalize_asset_attrs(attrs) do
    %{
      filename: Map.get(attrs, :filename) || Map.get(attrs, "filename"),
      content_type: Map.get(attrs, :content_type) || Map.get(attrs, "content_type")
    }
  end

  defp ensure_original_metadata(asset, binary_data, source_hash) do
    metadata = asset.metadata || %{}

    if metadata["source_blob_hash"] && metadata["variant_profile"] do
      asset
    else
      updated_metadata =
        binary_data
        |> image_metadata_from_binary()
        |> Map.merge(metadata)
        |> Map.merge(%{
          "source_blob_hash" => source_hash,
          "variant_profile" => "original"
        })

      case update_asset(asset, %{metadata: updated_metadata}) do
        {:ok, updated} -> updated
        {:error, _} -> asset
      end
    end
  end

  defp materialize_asset_for_purpose(binary_data, original, project, user, purpose, profile) do
    source_hash = original.blob_hash || BlobStore.compute_hash(binary_data)
    metadata = original.metadata || %{}

    if requires_variant?(purpose, original.content_type, metadata) do
      case get_asset_by_source_profile(project.id, source_hash, profile.profile) do
        %Asset{} = variant ->
          {:ok, variant, %{reused: true, action: :attach_existing_variant}}

        nil ->
          create_variant_asset(binary_data, original, project, user, source_hash, purpose, profile)
      end
    else
      {:ok, original, %{reused: true, action: :attach_existing_original}}
    end
  end

  defp create_variant_asset(binary_data, original, project, user, source_hash, purpose, profile) do
    case generate_variant_binary(binary_data, purpose, profile) do
      {:ok, webp_data} ->
        upload_variant_asset(webp_data, original, project, user, source_hash, profile)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_variant_binary(binary_data, purpose, %{target: %{width: width, height: height}})
       when purpose in [:avatar, :banner] do
    ImageProcessor.resize_to_webp(binary_data, width, height)
  end

  defp generate_variant_binary(binary_data, :scene_background, _profile) do
    ImageProcessor.to_webp(binary_data)
  end

  defp upload_variant_asset(webp_data, original, project, user, source_hash, profile) do
    dimensions = image_metadata_from_binary(webp_data)

    variant_attrs = %{
      filename: Path.rootname(original.filename) <> ".webp",
      content_type: "image/webp",
      metadata:
        Map.merge(dimensions, %{
          "is_variant" => true,
          "original_asset_id" => original.id,
          "source_blob_hash" => source_hash,
          "variant_profile" => profile.profile
        }),
      skip_variants: true
    }

    case upload_binary_and_create_asset(webp_data, variant_attrs, project, user) do
      {:ok, variant} ->
        link_variant_to_original(original, variant, profile.profile)
        {:ok, variant, %{reused: false, action: :created_variant}}

      error ->
        error
    end
  end

  defp image_metadata(%{width: width, height: height}) do
    %{}
    |> maybe_put_dimension("width", width)
    |> maybe_put_dimension("height", height)
  end

  defp image_metadata_from_binary(binary_data) do
    if ImageProcessor.available?() do
      case ImageProcessor.get_dimensions_from_binary(binary_data) do
        {:ok, %{width: width, height: height}} -> %{"width" => width, "height" => height}
        {:error, _} -> %{}
      end
    else
      %{}
    end
  end

  defp maybe_put_dimension(metadata, _key, nil), do: metadata
  defp maybe_put_dimension(metadata, key, value), do: Map.put(metadata, key, value)

  defp requires_variant?(purpose, content_type, metadata) do
    case ImageProcessor.needs_optimization?(content_type, metadata || %{}, purpose) do
      :skip -> false
      {:generate, _} -> true
    end
  end

  defp upload_decision_action(_original, %Asset{}, true), do: :attach_existing_variant
  defp upload_decision_action(%Asset{}, nil, true), do: :create_variant_from_existing_original
  defp upload_decision_action(%Asset{}, _variant, false), do: :attach_existing_original
  defp upload_decision_action(nil, _variant, true), do: :upload_original_and_create_variant
  defp upload_decision_action(nil, _variant, false), do: :upload_original_only

  defp decision_asset_id(_original, %Asset{id: id}, true), do: id
  defp decision_asset_id(%Asset{id: id}, _variant, false), do: id
  defp decision_asset_id(_original, _variant, _requires_variant?), do: nil

  defp get_asset_by_blob_hash(project_id, blob_hash) when is_binary(blob_hash) do
    Asset
    |> where(project_id: ^project_id, blob_hash: ^blob_hash)
    |> where([a], fragment("coalesce(?->>'is_variant', 'false') != 'true'", a.metadata))
    |> order_by([a], asc: a.inserted_at, asc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  defp get_asset_by_blob_hash(_project_id, _blob_hash), do: nil

  defp get_asset_by_source_profile(project_id, source_hash, profile) do
    Asset
    |> where([a], a.project_id == ^project_id)
    |> where([a], fragment("?->>'source_blob_hash' = ?", a.metadata, ^source_hash))
    |> where([a], fragment("?->>'variant_profile' = ?", a.metadata, ^profile))
    |> order_by([a], asc: a.inserted_at, asc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  defp maybe_schedule_variant(binary_data, asset, project, user, attrs) do
    purpose = Map.get(attrs, :purpose)
    skip = Map.get(attrs, :skip_variants, false)

    if purpose && !skip do
      schedule_variant_generation(binary_data, asset, project, user, purpose)
    end
  end

  defp schedule_variant_generation(binary_data, asset, project, user, purpose) do
    Task.Supervisor.start_child(Storyarn.TaskSupervisor, fn ->
      maybe_generate_variant(binary_data, asset, project, user, purpose)
    end)
  end

  defp maybe_generate_variant(binary_data, asset, project, user, purpose) do
    if not String.starts_with?(asset.content_type, "image/") or
         not ImageProcessor.available?() do
      {:ok, asset}
    else
      case ImageProcessor.needs_optimization?(asset.content_type, asset.metadata || %{}, purpose) do
        :skip ->
          {:ok, asset}

        {:generate, %{crop: true, width: w, height: h}} ->
          do_generate_variant(
            binary_data,
            asset,
            project,
            user,
            &ImageProcessor.resize_to_webp(&1, w, h)
          )

        {:generate, %{crop: false}} ->
          do_generate_variant(binary_data, asset, project, user, &ImageProcessor.to_webp/1)
      end
    end
  end

  defp do_generate_variant(binary_data, original_asset, project, user, process_fn) do
    case process_fn.(binary_data) do
      {:ok, webp_data} ->
        with :ok <- Billing.can_upload_asset_for_project?(project, byte_size(webp_data)) do
          upload_and_link_variant(webp_data, original_asset, project, user)
        end

      {:error, reason} ->
        Logger.warning("[ImageOptimization] Failed to generate WebP for asset #{original_asset.id}: #{inspect(reason)}")

        {:ok, original_asset}
    end
  end

  defp upload_and_link_variant(webp_data, original_asset, project, user) do
    variant_attrs = %{
      filename: Path.rootname(original_asset.filename) <> ".webp",
      content_type: "image/webp",
      metadata: %{"is_variant" => true, "original_asset_id" => original_asset.id},
      skip_variants: true
    }

    case upload_binary_and_create_asset(webp_data, variant_attrs, project, user) do
      {:ok, variant} ->
        link_variant_to_original(original_asset, variant)

      {:error, reason} ->
        Logger.warning(
          "[ImageOptimization] Failed to upload variant for asset #{original_asset.id}: " <>
            inspect(reason)
        )

        {:ok, original_asset}
    end
  end

  defp link_variant_to_original(original_asset, variant) do
    updated_metadata =
      Map.merge(original_asset.metadata || %{}, %{
        "web_url" => variant.url,
        "web_asset_id" => variant.id
      })

    case update_asset(original_asset, %{metadata: updated_metadata}) do
      {:ok, updated_original} ->
        {:ok, updated_original}

      {:error, reason} ->
        Logger.warning("[ImageOptimization] Failed to link variant to asset #{original_asset.id}: #{inspect(reason)}")

        {:ok, original_asset}
    end
  end

  defp link_variant_to_original(original_asset, variant, profile) do
    metadata = original_asset.metadata || %{}
    profiles = Map.get(metadata, "variant_asset_ids", %{})

    updated_metadata =
      Map.put(metadata, "variant_asset_ids", Map.put(profiles, profile, variant.id))

    case update_asset(original_asset, %{metadata: updated_metadata}) do
      {:ok, updated_original} ->
        {:ok, updated_original}

      {:error, reason} ->
        Logger.warning("[ImageOptimization] Failed to link variant to asset #{original_asset.id}: #{inspect(reason)}")

        {:ok, original_asset}
    end
  end

  defp do_create_asset(project, user, attrs, :generic), do: do_create_asset(project, user, attrs)

  defp do_create_asset(%Project{} = project, user, attrs, :sanitized_svg) do
    project
    |> create_asset_record(uploaded_by_id(user), attrs, :sanitized_svg)
    |> track_asset_created(user, attrs)
  end

  defp do_create_asset(project, nil, attrs), do: create_asset(project, attrs)
  defp do_create_asset(project, user, attrs), do: create_asset(project, user, attrs)

  defp uploaded_by_id(%User{id: id}), do: id
  defp uploaded_by_id(_), do: nil

  defp track_asset_created({:ok, asset}, user, attrs) do
    properties = asset_analytics_properties(asset, attrs)

    case user do
      %User{} -> Analytics.track(user, "asset uploaded", properties)
      _ -> Analytics.track_system("asset uploaded", properties)
    end

    {:ok, asset}
  end

  defp track_asset_created(result, _user, _attrs), do: result

  defp asset_analytics_properties(asset, attrs) do
    metadata = asset.metadata || %{}

    %{
      asset_type: asset_type_for_content_type(asset.content_type),
      content_type: asset.content_type,
      created_variant: metadata["is_variant"] == true,
      project_id: asset.project_id,
      purpose: analytics_value(Map.get(attrs, :purpose) || Map.get(attrs, "purpose")),
      size_bucket: size_bucket(asset.size)
    }
  end

  defp asset_type_for_content_type(content_type) when is_binary(content_type) do
    content_type
    |> String.split("/", parts: 2)
    |> List.first()
  end

  defp asset_type_for_content_type(_content_type), do: nil

  defp size_bucket(size) when is_integer(size) and size < 100 * 1024, do: "under_100kb"
  defp size_bucket(size) when is_integer(size) and size < 1024 * 1024, do: "100kb_to_1mb"
  defp size_bucket(size) when is_integer(size) and size < 10 * 1024 * 1024, do: "1mb_to_10mb"
  defp size_bucket(size) when is_integer(size), do: "over_10mb"
  defp size_bucket(_size), do: nil

  defp analytics_value(value) when is_atom(value), do: Atom.to_string(value)
  defp analytics_value(value), do: value

  defp extract_image_metadata(path, content_type) do
    if String.starts_with?(content_type, "image/") and ImageProcessor.available?() do
      case ImageProcessor.get_dimensions(path) do
        {:ok, %{width: w, height: h}} -> %{"width" => w, "height" => h}
        {:error, _} -> %{}
      end
    else
      %{}
    end
  end

  # =============================================================================
  # Asset Type Checks & Display
  # =============================================================================

  @doc """
  Returns the optimized web URL if a variant exists, otherwise the original URL.

  Delegates to `Storyarn.Assets.Asset.display_url/1`.
  """
  defdelegate display_url(asset), to: Asset

  @doc """
  Checks if an asset is an image based on its content type.

  Delegates to `Storyarn.Assets.Asset.image?/1`.
  """
  defdelegate image?(asset), to: Asset

  @doc """
  Checks if an asset is an audio file based on its content type.

  Delegates to `Storyarn.Assets.Asset.audio?/1`.
  """
  defdelegate audio?(asset), to: Asset

  @doc """
  Checks if a content type is in the allowed list for uploads.

  Delegates to `Storyarn.Assets.Asset.allowed_content_type?/1`.
  """
  defdelegate allowed_content_type?(content_type), to: Asset

  # =============================================================================
  # Storage Delegations
  # =============================================================================

  @doc """
  Uploads a file to storage.

  Delegates to `Storyarn.Assets.Storage.upload/3`.
  """
  defdelegate storage_upload(key, data, content_type), to: Storage, as: :upload

  @doc """
  Deletes a file from storage.

  Delegates to `Storyarn.Assets.Storage.delete/1`.
  """
  defdelegate storage_delete(key), to: Storage, as: :delete

  @doc """
  Downloads a file from storage as raw binary data.

  Delegates to `Storyarn.Assets.Storage.download/1`.
  """
  defdelegate storage_download(key), to: Storage, as: :download

  # =============================================================================
  # ImageProcessor Delegations
  # =============================================================================

  @doc """
  Checks if the image processor (ImageMagick) is available.

  Delegates to `Storyarn.Assets.ImageProcessor.available?/0`.
  """
  defdelegate image_processor_available?(), to: ImageProcessor, as: :available?

  @doc """
  Gets the dimensions of an image file.

  Delegates to `Storyarn.Assets.ImageProcessor.get_dimensions/1`.
  """
  defdelegate image_processor_get_dimensions(path), to: ImageProcessor, as: :get_dimensions

  @doc """
  Sanitizes a filename for safe storage.

  Strips path components, replaces unsafe characters, downcases, and limits length.
  """
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(filename) do
    filename
    |> String.split(~r/[\/\\]/)
    |> List.last()
    |> String.replace(~r/[^\w\.\-]/, "_")
    |> String.downcase()
    |> String.slice(0, 255)
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Lists all assets for a project for export.
  Ordered by insertion time.
  """
  @spec list_assets_for_export(integer()) :: [asset()]
  def list_assets_for_export(project_id) do
    Repo.all(from(a in Asset, where: a.project_id == ^project_id, order_by: [asc: a.inserted_at, asc: a.id]))
  end

  @doc """
  Counts all assets for a project.
  """
  @spec count_assets(integer(), list_opts()) :: non_neg_integer()
  def count_assets(project_id, opts \\ []) do
    from(a in Asset, where: a.project_id == ^project_id)
    |> apply_content_type_filter(opts)
    |> apply_images_only_filter(opts)
    |> apply_search_filter(opts)
    |> Repo.aggregate(:count)
  end

  # =============================================================================
  # Import helpers (raw insert, no side effects)
  # =============================================================================

  @doc """
  Creates an asset record for import. Raw insert with no upload logic or user tracking.
  Returns `{:ok, asset}` or `{:error, changeset}`.
  """
  @spec import_asset(integer(), attrs()) :: {:ok, asset()} | {:error, changeset()}
  def import_asset(project_id, attrs) do
    %Asset{project_id: project_id}
    |> Asset.create_changeset(attrs)
    |> Repo.insert()
  end
end
