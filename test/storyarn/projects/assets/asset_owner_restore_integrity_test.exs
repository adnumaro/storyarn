defmodule Storyarn.Projects.Assets.AssetOwnerRestoreIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Assets.Persistence.FlowRecord
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  test "sheet restore fails while its banner remains in asset trash", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)
    sheet = sheet_fixture(project, %{banner_asset_id: asset.id})

    assert {:ok, deleted_sheet} = Sheets.delete_sheet(sheet)
    assert {:ok, _trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert_inactive_asset_error(Sheets.restore_sheet(deleted_sheet), asset.id)
    assert Repo.get!(Sheet, sheet.id).deleted_at
  end

  test "gallery block restore fails while a gallery asset remains in trash", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)
    sheet = sheet_fixture(project)
    block = block_fixture(sheet, %{type: "gallery"})
    assert {:ok, _gallery_image} = Sheets.add_gallery_image(block, asset.id)

    assert {:ok, deleted_block} = Sheets.delete_block(block)
    assert {:ok, _trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert_inactive_asset_error(Sheets.restore_block(deleted_block), asset.id)
    assert Repo.get!(Block, block.id).deleted_at
  end

  test "scene restore validates assets owned by recursively restored children", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)
    parent = scene_fixture(project, %{name: "Parent"})
    child = scene_fixture(project, %{name: "Child", parent_id: parent.id, background_asset_id: asset.id})

    assert {:ok, deleted_parent} = Scenes.delete_scene(parent)
    assert Repo.get!(Scene, child.id).deleted_at
    assert {:ok, _trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert_inactive_asset_error(Scenes.restore_scene(deleted_parent), asset.id)
    assert Repo.get!(Scene, parent.id).deleted_at
    assert Repo.get!(Scene, child.id).deleted_at
  end

  test "sequence restore validates track assets before reactivation", %{
    project: project,
    user: user
  } do
    asset = audio_asset_fixture(project, user)
    flow = flow_fixture(project)
    assert {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Music"})
    assert {:ok, _track} = Flows.upsert_sequence_track(sequence.id, "music", %{"asset_id" => asset.id})

    assert {:ok, deleted_sequence} = Flows.delete_sequence(sequence)
    assert {:ok, _trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert_inactive_asset_error(Flows.restore_sequence(deleted_sequence), asset.id)
    assert Repo.get!(FlowNodeRecord, sequence.id).deleted_at
  end

  test "flow restore validates sequence assets before publishing the flow", %{
    project: project,
    user: user
  } do
    asset = audio_asset_fixture(project, user)
    flow = flow_fixture(project)
    assert {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Music"})
    assert {:ok, _track} = Flows.upsert_sequence_track(sequence.id, "music", %{"asset_id" => asset.id})

    assert {:ok, deleted_flow} = Flows.delete_flow(flow)
    assert {:ok, _trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert_inactive_asset_error(Flows.restore_flow(deleted_flow), asset.id)
    assert Repo.get!(FlowRecord, flow.id).deleted_at
  end

  test "generic node restore cannot bypass sequence asset validation", %{
    project: project,
    user: user
  } do
    asset = audio_asset_fixture(project, user)
    flow = flow_fixture(project)
    assert {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Music"})
    assert {:ok, _track} = Flows.upsert_sequence_track(sequence.id, "music", %{"asset_id" => asset.id})

    assert {:ok, _deleted_sequence} = Flows.delete_sequence(sequence)
    assert {:ok, _trashed_asset} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert_inactive_asset_error(Flows.restore_node(flow.id, sequence.id), asset.id)
    assert Repo.get!(FlowNodeRecord, sequence.id).deleted_at
  end

  defp assert_inactive_asset_error(result, asset_id) do
    assert {:error, {:invalid_project_reference, _context, ^asset_id}} = result
  end
end
