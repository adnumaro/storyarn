defmodule Storyarn.Assets.ActiveAssetAssociationsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Sheets

  test "asset associations expose active rows but hide rows in asset trash" do
    user = user_fixture()
    project = project_fixture(user)
    image = image_asset_fixture(project, user)
    audio = audio_asset_fixture(project, user)

    sheet = sheet_fixture(project, %{banner_asset_id: image.id})
    {:ok, avatar} = Sheets.add_avatar(sheet, image.id)
    gallery_block = block_fixture(sheet, %{type: "gallery"})
    {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, image.id)

    flow = flow_fixture(project)
    {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Opening"})

    {:ok, visual_layer} =
      Flows.create_sequence_visual_layer(sequence.id, %{
        "asset_id" => image.id,
        "kind" => "backdrop"
      })

    {:ok, track} =
      Flows.upsert_sequence_track(sequence.id, "music", %{"asset_id" => audio.id})

    scene = scene_fixture(project, %{background_asset_id: image.id})
    pin = pin_fixture(scene, %{"icon_asset_id" => image.id})

    zone =
      zone_fixture(scene, %{
        "label_mode" => "icon",
        "label_icon_asset_id" => image.id
      })

    text = localized_text_fixture(project.id)

    {:ok, voiced_text} =
      Localization.update_text(text, %{
        vo_asset_id: audio.id,
        vo_status: "recorded"
      })

    image_id = image.id
    audio_id = audio.id

    assert %Asset{id: ^image_id} = Repo.preload(sheet, :banner_asset).banner_asset
    assert [%{asset: %Asset{id: ^image_id}}] = Repo.preload(sheet, avatars: :asset).avatars
    assert %Asset{id: ^image_id} = Repo.preload(gallery_image, :asset).asset
    assert %{id: ^image_id} = Repo.preload(visual_layer, :asset).asset
    assert %{id: ^audio_id} = Repo.preload(track, :asset).asset
    assert %{id: ^image_id} = Repo.preload(scene, :background_asset).background_asset
    assert %{id: ^image_id} = Repo.preload(pin, :icon_asset).icon_asset
    assert %{id: ^image_id} = Repo.preload(zone, :label_icon_asset).label_icon_asset
    assert %{id: ^audio_id} = Repo.preload(voiced_text, :vo_asset).vo_asset

    trash_asset_rows!([image.id, audio.id], user.id)

    loaded_sheet = Repo.preload(sheet, [:banner_asset, avatars: :asset], force: true)
    loaded_gallery_image = Repo.preload(gallery_image, :asset, force: true)
    loaded_visual_layer = Repo.preload(visual_layer, :asset, force: true)
    loaded_track = Repo.preload(track, :asset, force: true)
    loaded_scene = Repo.preload(scene, :background_asset, force: true)
    loaded_pin = Repo.preload(pin, :icon_asset, force: true)
    loaded_zone = Repo.preload(zone, :label_icon_asset, force: true)
    loaded_text = Repo.preload(voiced_text, :vo_asset, force: true)

    assert loaded_sheet.banner_asset == nil
    assert [%{asset: nil}] = loaded_sheet.avatars
    assert loaded_gallery_image.asset == nil
    assert loaded_visual_layer.asset == nil
    assert loaded_track.asset == nil
    assert loaded_scene.background_asset == nil
    assert loaded_pin.icon_asset == nil
    assert loaded_zone.label_icon_asset == nil
    assert loaded_text.vo_asset == nil

    assert Repo.reload!(sheet).banner_asset_id == image.id
    assert Repo.reload!(avatar).asset_id == image.id
    assert Repo.reload!(gallery_image).asset_id == image.id
    assert Repo.reload!(visual_layer).asset_id == image.id
    assert Repo.reload!(track).asset_id == audio.id
    assert Repo.reload!(scene).background_asset_id == image.id
    assert Repo.reload!(pin).icon_asset_id == image.id
    assert Repo.reload!(zone).label_icon_asset_id == image.id
    assert Repo.reload!(voiced_text).vo_asset_id == audio.id
  end

  defp trash_asset_rows!(asset_ids, user_id) do
    {count, _rows} =
      Repo.update_all(
        from(asset in Asset, where: asset.id in ^asset_ids),
        set: [
          deleted_at: Storyarn.Shared.TimeHelpers.now(),
          deleted_by_id: user_id,
          deletion_reason: "user",
          deletion_generation: 1
        ]
      )

    assert count == length(asset_ids)
  end
end
