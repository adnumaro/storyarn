defmodule Storyarn.Flows.EditorCatalogTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Persistence.BlockRecord
  alias Storyarn.Flows.Persistence.SceneRecord
  alias Storyarn.Flows.Persistence.SheetRecord
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.PrivateMedia

  describe "load_editor_catalog/1" do
    test "preserves the editor's current Sheet and Scene presentation contract" do
      user = user_fixture()
      project = project_fixture(user)

      optimized_banner = image_asset_fixture(project, user, %{filename: "banner-web.webp"})

      original_banner =
        image_asset_fixture(project, user, %{
          filename: "banner-original.png",
          metadata: %{"web_asset_id" => optimized_banner.id}
        })

      sheet = sheet_fixture(project, %{name: "Hero", color: "#123456"})

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^sheet.id),
        set: [banner_asset_id: original_banner.id]
      )

      avatar_asset = image_asset_fixture(project, user, %{filename: "hero-avatar.png"})
      assert {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "neutral"})

      gallery_block = block_fixture(sheet, %{type: "gallery", config: %{"label" => "Portraits"}})
      gallery_asset = image_asset_fixture(project, user, %{filename: "hero-gallery.png"})
      assert {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)
      assert {:ok, _gallery_image} = Sheets.update_gallery_image(gallery_image, %{label: "Portrait"})

      scene = scene_fixture(project, %{name: "Castle"})

      catalog = Flows.load_editor_catalog(project.id)
      legacy_sheets = Sheets.list_all_sheets(project.id)
      legacy_gallery = Sheets.batch_load_gallery_data_by_sheet(project.id)

      assert FormHelpers.sheets_map(catalog.sheets, catalog.gallery_by_sheet) ==
               FormHelpers.sheets_map(legacy_sheets, legacy_gallery)

      assert catalog.scenes ==
               project.id
               |> Scenes.list_scenes()
               |> Enum.map(&Map.take(&1, [:id, :name]))

      assert catalog.scenes == [%{id: scene.id, name: "Castle"}]

      [catalog_sheet] = catalog.sheets
      [legacy_sheet] = legacy_sheets

      assert PrivateMedia.asset_url(catalog_sheet.banner_asset) ==
               PrivateMedia.asset_url(legacy_sheet.banner_asset)

      assert catalog_sheet.banner_asset == %{
               id: optimized_banner.id,
               filename: "banner-original.png"
             }

      assert %{asset: %{filename: "hero-gallery.png"}, label: "Portrait"} = List.first(catalog.gallery_by_sheet[sheet.id])
    end

    test "isolates projects, excludes soft-deleted rows and preserves consumer ordering" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)
      deleted_at = TimeHelpers.now()

      second_sheet = sheet_fixture(project, %{name: "Second"})
      first_sheet = sheet_fixture(project, %{name: "First"})
      deleted_sheet = sheet_fixture(project, %{name: "Deleted"})
      _foreign_sheet = sheet_fixture(other_project, %{name: "Foreign"})

      set_sheet_position(first_sheet.id, 0)
      set_sheet_position(second_sheet.id, 1)

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^deleted_sheet.id),
        set: [deleted_at: deleted_at]
      )

      active_gallery = block_fixture(first_sheet, %{type: "gallery"})
      deleted_gallery = block_fixture(first_sheet, %{type: "gallery"})
      active_asset = image_asset_fixture(project, user)
      deleted_asset = image_asset_fixture(project, user)
      assert {:ok, active_image} = Sheets.add_gallery_image(active_gallery, active_asset.id)
      assert {:ok, _deleted_image} = Sheets.add_gallery_image(deleted_gallery, deleted_asset.id)

      Repo.update_all(
        from(record in BlockRecord, where: record.id == ^deleted_gallery.id),
        set: [deleted_at: deleted_at]
      )

      second_scene = scene_fixture(project, %{name: "Second scene"})
      first_scene = scene_fixture(project, %{name: "First scene"})
      deleted_scene = scene_fixture(project, %{name: "Deleted scene"})
      _foreign_scene = scene_fixture(other_project, %{name: "Foreign scene"})

      set_scene_position(first_scene.id, 0)
      set_scene_position(second_scene.id, 1)

      Repo.update_all(
        from(record in SceneRecord, where: record.id == ^deleted_scene.id),
        set: [deleted_at: deleted_at]
      )

      catalog = Flows.load_editor_catalog(project.id)

      assert Enum.map(catalog.sheets, & &1.id) == [first_sheet.id, second_sheet.id]
      assert Map.keys(catalog.gallery_by_sheet) == [first_sheet.id]
      assert Enum.map(catalog.gallery_by_sheet[first_sheet.id], & &1.id) == [active_image.id]
      assert Enum.map(catalog.scenes, & &1.id) == [first_scene.id, second_scene.id]
    end

    test "filters deleted media while retaining the owning records" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)
      sheet = sheet_fixture(project, %{name: "Hero"})

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^sheet.id),
        set: [banner_asset_id: asset.id]
      )

      Repo.update_all(
        from(record in Asset, where: record.id == ^asset.id),
        set: [deleted_at: TimeHelpers.now(), deletion_reason: "system", deletion_generation: 1]
      )

      assert %{sheets: [%{id: id, banner_asset: nil}]} = Flows.load_editor_catalog(project.id)
      assert id == sheet.id
    end
  end

  describe "get_preview_speaker_name/2" do
    test "returns only the current active speaker name within the project" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)
      speaker = sheet_fixture(project, %{name: "Ada Lovelace"})

      assert Flows.get_preview_speaker_name(project.id, speaker.id) ==
               Sheets.get_sheet(project.id, speaker.id).name

      assert Flows.get_preview_speaker_name(other_project.id, speaker.id) == nil
      assert Flows.get_preview_speaker_name(project.id, -1) == nil
    end

    test "returns nil after the source speaker is soft-deleted" do
      project = project_fixture(user_fixture())
      speaker = sheet_fixture(project, %{name: "Deleted speaker"})

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^speaker.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert Flows.get_preview_speaker_name(project.id, speaker.id) == nil
    end
  end

  describe "search_mentions/2" do
    test "returns active Sheet and Flow mentions in stable name order within one project" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)

      sheet = sheet_fixture(project, %{name: "Alpha sheet", shortcut: "alpha"})
      flow = flow_fixture(project, %{name: "Zulu flow", shortcut: "zulu"})
      deleted_sheet = sheet_fixture(project, %{name: "Deleted sheet", shortcut: "deleted-sheet"})
      deleted_flow = flow_fixture(project, %{name: "Deleted flow", shortcut: "deleted-flow"})
      _foreign_sheet = sheet_fixture(other_project, %{name: "Foreign sheet", shortcut: "foreign"})
      _foreign_flow = flow_fixture(other_project, %{name: "Foreign flow", shortcut: "foreign-flow"})

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^deleted_sheet.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      Repo.update_all(
        from(record in Flow, where: record.id == ^deleted_flow.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert Flows.search_mentions(project.id, "") == [
               %{id: sheet.id, type: "sheet", name: "Alpha sheet", shortcut: "alpha"},
               %{id: flow.id, type: "flow", name: "Zulu flow", shortcut: "zulu"}
             ]
    end

    test "searches names and shortcuts and caps the combined result" do
      project = project_fixture(user_fixture())

      for index <- 1..21 do
        sheet_fixture(project, %{
          name: "Candidate #{String.pad_leading(to_string(index), 2, "0")}",
          shortcut: "candidate-#{index}"
        })
      end

      shortcut_match = flow_fixture(project, %{name: "A shortcut match", shortcut: "candidate-flow"})
      results = Flows.search_mentions(project.id, "candidate")

      assert length(results) == 20
      assert Enum.map(results, & &1.name) == Enum.sort(Enum.map(results, & &1.name))
      assert Enum.any?(results, &(&1.id == shortcut_match.id and &1.type == "flow"))
    end
  end

  describe "speaker picker read model" do
    test "searches active speakers within one project" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)
      matching = sheet_fixture(project, %{name: "Hero Sheet", shortcut: "hero"})
      deleted = sheet_fixture(project, %{name: "Hero Deleted", shortcut: "hero-deleted"})
      _foreign = sheet_fixture(other_project, %{name: "Hero Foreign", shortcut: "hero-foreign"})

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^deleted.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert Flows.search_speaker_options(project.id, "hero", limit: 10) ==
               {[%{id: matching.id, name: matching.name}], false}
    end

    test "retains a selected speaker outside the bounded first page" do
      project = project_fixture(user_fixture())
      selected = sheet_fixture(project, %{name: "Selected speaker"})

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^selected.id),
        set: [updated_at: ~U[2020-01-01 00:00:00Z]]
      )

      for index <- 1..3 do
        sheet_fixture(project, %{name: "Newer speaker #{index}"})
      end

      {results, has_more} =
        Flows.search_speaker_options(project.id, "", limit: 1, selected_id: selected.id)

      assert has_more
      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == selected.id))
    end
  end

  describe "asset picker read model" do
    test "searches active assets by project and media kind" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)
      matching = image_asset_fixture(project, user, %{filename: "hero-portrait.png"})
      deleted = image_asset_fixture(project, user, %{filename: "hero-deleted.png"})
      _audio = audio_asset_fixture(project, user, %{filename: "hero-theme.mp3"})
      _foreign = image_asset_fixture(other_project, user, %{filename: "hero-foreign.png"})

      assert {:ok, _deleted} = Assets.delete_asset(deleted)

      assert Flows.search_asset_options(project.id, "image", query: "hero", limit: 10) ==
               {[
                  %{
                    id: matching.id,
                    filename: matching.filename,
                    content_type: matching.content_type,
                    metadata: matching.metadata
                  }
                ], false}
    end

    test "retains selected assets outside the bounded first page" do
      user = user_fixture()
      project = project_fixture(user)
      selected = image_asset_fixture(project, user, %{filename: "selected.png"})

      Repo.update_all(
        from(record in Asset, where: record.id == ^selected.id),
        set: [inserted_at: ~U[2020-01-01 00:00:00Z]]
      )

      for index <- 1..3 do
        image_asset_fixture(project, user, %{filename: "newer-#{index}.png"})
      end

      {results, has_more} =
        Flows.search_asset_options(project.id, "image", limit: 1, selected_id: selected.id)

      assert has_more
      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == selected.id))
    end
  end

  describe "Flow schema boundary" do
    test "keeps foreign references as scalar ids instead of foreign associations" do
      assert Flow.__schema__(:type, :project_id) == :id
      assert Flow.__schema__(:type, :scene_id) == :id
      assert Flow.__schema__(:type, :current_version_id) == :id

      associations = Flow.__schema__(:associations)
      refute :project in associations
      refute :scene in associations
      refute :current_version in associations
    end
  end

  defp set_sheet_position(sheet_id, position) do
    Repo.update_all(from(record in SheetRecord, where: record.id == ^sheet_id), set: [position: position])
  end

  defp set_scene_position(scene_id, position) do
    Repo.update_all(from(record in SceneRecord, where: record.id == ^scene_id), set: [position: position])
  end
end
