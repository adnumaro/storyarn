defmodule Storyarn.Versioning.Builders.PortableSnapshotValidationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias StoryarnTest.ProjectsSceneBuilderTestAdapter, as: SceneBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{project: project}
  end

  test "sheet portable validation rejects malformed nested blocks", %{project: project} do
    sheet = sheet_fixture(project)
    block = block_fixture(sheet)
    snapshot = SheetBuilder.build_snapshot(sheet)

    assert :ok = SheetBuilder.validate_portable_snapshot(snapshot)

    malformed =
      update_in(snapshot, ["blocks"], fn [entry | rest] ->
        [Map.put(entry, "position", "not-an-integer") | rest]
      end)

    assert {:error, {:invalid_snapshot, {:invalid_payload, :block, block_id, "position", "not-an-integer"}}} =
             SheetBuilder.validate_portable_snapshot(malformed)

    assert block_id == block.id
  end

  test "flow portable validation rejects malformed nested nodes", %{project: project} do
    flow = flow_fixture(project)
    snapshot = FlowBuilder.build_snapshot(flow)

    assert :ok = FlowBuilder.validate_portable_snapshot(snapshot)

    malformed =
      update_in(snapshot, ["nodes"], fn [entry | rest] ->
        [Map.put(entry, "position_x", "not-a-number") | rest]
      end)

    assert {:error, {:invalid_snapshot_field, :node, "position_x", "not-a-number"}} =
             FlowBuilder.validate_portable_snapshot(malformed)
  end

  test "scene portable validation rejects malformed nested layers", %{project: project} do
    scene = scene_fixture(project)
    snapshot = SceneBuilder.build_snapshot(scene)

    assert :ok = SceneBuilder.validate_portable_snapshot(snapshot)

    assert {:error, :scene_snapshot_requires_at_least_one_layer} =
             snapshot
             |> Map.put("layers", [])
             |> SceneBuilder.validate_portable_snapshot()
  end
end
