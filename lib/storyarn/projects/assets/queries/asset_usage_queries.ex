defmodule Storyarn.Projects.Assets.Queries.AssetUsageQueries do
  @moduledoc """
  Read-only usage projection for Project-owned asset families.

  It deliberately includes references from trashed content because permanent
  asset deletion must expose every relationship that can lose data.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.AssetFamily
  alias Storyarn.Projects.Assets.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Assets.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Assets.Persistence.SequenceConfigRecord, as: SequenceConfig
  alias Storyarn.Projects.Assets.Persistence.SequenceTrackRecord, as: SequenceTrack
  alias Storyarn.Projects.Assets.Persistence.SequenceVisualLayerRecord, as: SequenceVisualLayer
  alias Storyarn.Projects.Persistence.BlockGalleryImageRecord, as: BlockGalleryImage
  alias Storyarn.Projects.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.Persistence.LocalizedTextRecord, as: LocalizedText
  alias Storyarn.Projects.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.Persistence.SceneZoneRecord, as: SceneZone
  alias Storyarn.Projects.Persistence.SheetAvatarRecord, as: SheetAvatar
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Repo

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
    get_asset_usages_for_ids(project_id, [asset_id])
  end

  defp get_asset_usages_for_ids(_project_id, []), do: empty_asset_usages()

  defp get_asset_usages_for_ids(project_id, asset_ids) do
    asset_ids = Enum.uniq(asset_ids)

    %{
      asset_metadata_links: list_asset_metadata_links(project_id, asset_ids),
      flow_nodes: list_flow_nodes_using_assets(project_id, asset_ids),
      sequence_visual_layers: list_sequence_visual_layers_using_assets(project_id, asset_ids),
      sequence_tracks: list_sequence_tracks_using_assets(project_id, asset_ids),
      sheet_avatars: list_sheet_avatars_using_assets(project_id, asset_ids),
      sheet_banners: list_sheet_banners_using_assets(project_id, asset_ids),
      scene_backgrounds: list_scenes_using_assets_as_background(project_id, asset_ids),
      scene_pin_icons: list_scene_pins_using_assets_as_icon(project_id, asset_ids),
      scene_zone_icons: list_scene_zones_using_assets_as_icon(project_id, asset_ids),
      localized_voiceovers: list_localized_voiceovers_using_assets(project_id, asset_ids),
      gallery_images: list_gallery_images_using_assets(project_id, asset_ids)
    }
  end

  @doc """
  Returns usage references aggregated across an asset's active family.

  Family membership uses the same undirected metadata graph as recoverable
  trash. Lists are deduplicated so callers can use this map as a complete
  preview of the references checked before moving the family to trash.
  """
  @spec get_asset_family_usages(integer(), integer()) :: %{
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
  def get_asset_family_usages(project_id, asset_id) do
    usages =
      project_id
      |> active_family_ids(asset_id)
      |> then(&get_asset_usages_for_ids(project_id, &1))

    # Trash expands any selected member to the complete transitive family, so
    # keep every other linked member in its preview and suppress only the row
    # that would report the selected asset as its own usage.
    Map.update!(usages, :asset_metadata_links, fn links ->
      Enum.reject(links, &(&1.id == asset_id))
    end)
  end

  defp active_family_ids(project_id, asset_id)
       when is_integer(project_id) and project_id > 0 and is_integer(asset_id) and asset_id > 0 do
    assets =
      Repo.all(
        from(asset in Asset,
          where: asset.project_id == ^project_id,
          order_by: [asc: asset.id]
        )
      )

    case Enum.find(assets, &(&1.id == asset_id)) do
      %Asset{deleted_at: nil} ->
        family_ids = AssetFamily.component_ids(assets, [asset_id])

        for %Asset{id: id, deleted_at: nil} <- assets,
            MapSet.member?(family_ids, id),
            do: id

      _missing_or_trashed ->
        []
    end
  end

  defp active_family_ids(_project_id, _asset_id), do: []

  defp empty_asset_usages do
    %{
      asset_metadata_links: [],
      flow_nodes: [],
      sequence_visual_layers: [],
      sequence_tracks: [],
      sheet_avatars: [],
      sheet_banners: [],
      scene_backgrounds: [],
      scene_pin_icons: [],
      scene_zone_icons: [],
      localized_voiceovers: [],
      gallery_images: []
    }
  end

  defp list_asset_metadata_links(project_id, asset_ids) do
    asset_id_strings = Enum.map(asset_ids, &to_string/1)

    project_id
    |> list_assets_with_metadata_links(asset_id_strings)
    |> Enum.map(fn asset ->
      %{
        id: asset.id,
        filename: asset.filename,
        relations: asset_metadata_link_relations(asset.metadata || %{}, asset_id_strings)
      }
    end)
  end

  defp list_assets_with_metadata_links(project_id, asset_id_strings) do
    Repo.all(
      from(asset in Asset,
        where: asset.project_id == ^project_id,
        where:
          fragment("?->>'web_asset_id' = ANY(?)", asset.metadata, ^asset_id_strings) or
            fragment("?->>'original_asset_id' = ANY(?)", asset.metadata, ^asset_id_strings) or
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
                WHERE variant_link.value = ANY(?)
              )
              """,
              asset.metadata,
              asset.metadata,
              ^asset_id_strings
            ),
        order_by: [asc: asset.filename, asc: asset.id]
      )
    )
  end

  defp asset_metadata_link_relations(metadata, asset_id_strings) do
    []
    |> maybe_add_metadata_relation(
      metadata_id_matches_any?(metadata["web_asset_id"], asset_id_strings),
      "web_variant"
    )
    |> maybe_add_metadata_relation(
      metadata_id_matches_any?(metadata["original_asset_id"], asset_id_strings),
      "original"
    )
    |> maybe_add_metadata_relation(profile_variant_link?(metadata, asset_id_strings), "profile_variant")
    |> Enum.reverse()
  end

  defp profile_variant_link?(%{"variant_asset_ids" => profiles}, asset_id_strings) when is_map(profiles) do
    Enum.any?(profiles, fn {_profile, asset_id} ->
      metadata_id_matches_any?(asset_id, asset_id_strings)
    end)
  end

  defp profile_variant_link?(_metadata, _asset_id_strings), do: false

  defp maybe_add_metadata_relation(relations, true, relation), do: [relation | relations]
  defp maybe_add_metadata_relation(relations, false, _relation), do: relations

  defp metadata_id_matches?(value, asset_id_string) when is_integer(value),
    do: Integer.to_string(value) == asset_id_string

  defp metadata_id_matches?(value, asset_id_string) when is_binary(value), do: value == asset_id_string

  defp metadata_id_matches?(_value, _asset_id_string), do: false

  defp metadata_id_matches_any?(value, asset_id_strings) do
    Enum.any?(asset_id_strings, &metadata_id_matches?(value, &1))
  end

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

  defp list_flow_nodes_using_assets(project_id, asset_ids) do
    asset_ids = Enum.map(asset_ids, &to_string/1)

    Repo.all(
      from(node in FlowNode,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        where:
          flow.project_id == ^project_id and
            fragment("?->>'audio_asset_id' = ANY(?)", node.data, ^asset_ids),
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

  defp list_sequence_visual_layers_using_assets(project_id, asset_ids) do
    Repo.all(
      from(layer in SequenceVisualLayer,
        join: node in FlowNode,
        on: layer.flow_node_id == node.id,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        left_join: config in SequenceConfig,
        on: config.flow_node_id == node.id,
        where: flow.project_id == ^project_id and layer.asset_id in ^asset_ids,
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

  defp list_sequence_tracks_using_assets(project_id, asset_ids) do
    Repo.all(
      from(track in SequenceTrack,
        join: node in FlowNode,
        on: track.flow_node_id == node.id,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        left_join: config in SequenceConfig,
        on: config.flow_node_id == node.id,
        where: flow.project_id == ^project_id and track.asset_id in ^asset_ids,
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

  defp list_sheet_avatars_using_assets(project_id, asset_ids) do
    Repo.all(
      from(sheet in Sheet,
        join: avatar in SheetAvatar,
        on: avatar.sheet_id == sheet.id,
        where: sheet.project_id == ^project_id and avatar.asset_id in ^asset_ids,
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

  defp list_sheet_banners_using_assets(project_id, asset_ids) do
    Repo.all(
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id and sheet.banner_asset_id in ^asset_ids,
        order_by: [asc: sheet.name, asc: sheet.id],
        select: %{
          id: sheet.id,
          name: sheet.name,
          trashed: not is_nil(sheet.deleted_at)
        }
      )
    )
  end

  defp list_localized_voiceovers_using_assets(project_id, asset_ids) do
    Repo.all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and
            text.vo_asset_id in ^asset_ids,
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

  defp list_gallery_images_using_assets(project_id, asset_ids) do
    Repo.all(
      from(gallery_image in BlockGalleryImage,
        join: block in Block,
        on: block.id == gallery_image.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and
            gallery_image.asset_id in ^asset_ids,
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

  defp list_scenes_using_assets_as_background(project_id, asset_ids) do
    Repo.all(
      from(scene in Scene,
        where: scene.project_id == ^project_id and scene.background_asset_id in ^asset_ids,
        order_by: [asc: scene.name, asc: scene.id],
        select: %{
          id: scene.id,
          name: scene.name,
          trashed: not is_nil(scene.deleted_at)
        }
      )
    )
  end

  defp list_scene_pins_using_assets_as_icon(project_id, asset_ids) do
    Repo.all(
      from(pin in ScenePin,
        join: scene in Scene,
        on: pin.scene_id == scene.id,
        where: scene.project_id == ^project_id and pin.icon_asset_id in ^asset_ids,
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

  defp list_scene_zones_using_assets_as_icon(project_id, asset_ids) do
    Repo.all(
      from(zone in SceneZone,
        join: scene in Scene,
        on: zone.scene_id == scene.id,
        where: scene.project_id == ^project_id and zone.label_icon_asset_id in ^asset_ids,
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
end
