defmodule Storyarn.Versioning.RestorePolicyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.ProjectSnapshotCrud
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.VersionCrud

  setup do
    original_config =
      Application.get_env(:storyarn, RestorePolicy)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, original_config)
      end
    end)

    :ok
  end

  test "missing, unknown, and non-boolean configuration values fail closed" do
    Application.delete_env(:storyarn, RestorePolicy)

    refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?(:project_snapshot_restore)
    refute RestorePolicy.enabled?(:deleted_project_recovery)
    refute RestorePolicy.enabled?({:entity_version_restore, "unknown"})
    refute RestorePolicy.enabled?(:unknown_action)

    Application.put_env(
      :storyarn,
      RestorePolicy,
      sheet_version_restore: "true",
      project_snapshot_restore: 1,
      deleted_project_recovery: nil
    )

    refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?(:project_snapshot_restore)
    refute RestorePolicy.enabled?(:deleted_project_recovery)

    for invalid_config <- [%{}, nil, ["invalid"]] do
      Application.put_env(:storyarn, RestorePolicy, invalid_config)

      refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
      refute RestorePolicy.enabled?(:project_snapshot_restore)
      refute RestorePolicy.enabled?(:deleted_project_recovery)
    end
  end

  test "entity restore surfaces are enabled independently only by literal true" do
    Application.put_env(
      :storyarn,
      RestorePolicy,
      sheet_version_restore: true,
      flow_version_restore: false,
      scene_version_restore: false,
      project_snapshot_restore: true,
      deleted_project_recovery: false
    )

    assert RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?({:entity_version_restore, "flow"})
    refute RestorePolicy.enabled?({:entity_version_restore, "scene"})
    refute RestorePolicy.enabled?(:project_snapshot_restore)
    refute RestorePolicy.enabled?(:deleted_project_recovery)
  end

  test "project snapshot restore requires its own switch and every entity dependency" do
    base = [
      sheet_version_restore: true,
      flow_version_restore: true,
      scene_version_restore: true,
      project_snapshot_restore: true,
      deleted_project_recovery: false
    ]

    Application.put_env(:storyarn, RestorePolicy, base)
    assert RestorePolicy.enabled?(:project_snapshot_restore)

    for key <- [
          :sheet_version_restore,
          :flow_version_restore,
          :scene_version_restore,
          :project_snapshot_restore
        ] do
      Application.put_env(:storyarn, RestorePolicy, Keyword.put(base, key, false))
      refute RestorePolicy.enabled?(:project_snapshot_restore)
    end
  end

  test "the public facade rejects restore before mutating or creating a safety version" do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Original"})
    block = block_fixture(sheet)

    {:ok, version} =
      Versioning.create_version("sheet", sheet, project.id, user.id, title: "Restore target")

    {:ok, changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed"})

    policy =
      Application.get_env(:storyarn, RestorePolicy, [])

    Application.put_env(
      :storyarn,
      RestorePolicy,
      Keyword.put(policy, :sheet_version_restore, false)
    )

    assert {:error, :restore_temporarily_disabled} =
             Versioning.restore_version(
               "sheet",
               changed_sheet,
               version,
               user_id: user.id
             )

    assert {:error, :restore_temporarily_disabled} =
             VersionCrud.restore_version(
               "sheet",
               changed_sheet,
               version,
               user_id: user.id
             )

    assert Sheets.get_sheet(project.id, sheet.id).name == "Changed"
    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == [block.id]
    assert Versioning.count_versions("sheet", sheet.id) == 1
  end

  test "project restore is rejected at the CRUD and builder boundaries" do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Original"})
    block = block_fixture(sheet)

    snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

    {:ok, snapshot} =
      Versioning.create_project_snapshot(project.id, user.id, title: "Restore target")

    {:ok, _changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed"})

    policy =
      Application.get_env(:storyarn, RestorePolicy, [])

    Application.put_env(
      :storyarn,
      RestorePolicy,
      Keyword.put(policy, :project_snapshot_restore, false)
    )

    assert {:error, :restore_temporarily_disabled} =
             ProjectSnapshotCrud.restore_snapshot(
               project.id,
               snapshot,
               user_id: user.id
             )

    assert {:error, :restore_temporarily_disabled} =
             ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot_data)

    assert Sheets.get_sheet(project.id, sheet.id).name == "Changed"
    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == [block.id]
    assert Versioning.count_project_snapshots(project.id) == 1
  end

  test "entity builders reject direct calls without a policy-scoped action" do
    user = user_fixture()
    project = project_fixture(user)

    sheet = sheet_fixture(project)
    _block = block_fixture(sheet)
    sheet_snapshot = SheetBuilder.build_snapshot(sheet)
    sheet_block_ids = Enum.map(Sheets.list_blocks(sheet.id), & &1.id)

    flow = flow_fixture(project)
    _node = node_fixture(flow)
    flow_snapshot = FlowBuilder.build_snapshot(flow)
    flow_node_ids = Enum.map(Flows.list_nodes(flow.id), & &1.id)

    scene = scene_fixture(project)
    _layer = layer_fixture(scene)
    scene_snapshot = SceneBuilder.build_snapshot(scene)
    scene_layer_ids = Enum.map(Scenes.list_layers(scene.id), & &1.id)

    assert {:error, :restore_temporarily_disabled} =
             SheetBuilder.restore_snapshot(sheet, sheet_snapshot)

    assert {:error, :restore_temporarily_disabled} =
             FlowBuilder.restore_snapshot(flow, flow_snapshot)

    assert {:error, :restore_temporarily_disabled} =
             SceneBuilder.restore_snapshot(scene, scene_snapshot)

    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == sheet_block_ids
    assert Enum.map(Flows.list_nodes(flow.id), & &1.id) == flow_node_ids
    assert Enum.map(Scenes.list_layers(scene.id), & &1.id) == scene_layer_ids
  end

  test "project restore action cannot bypass a disabled entity switch" do
    user = user_fixture()
    project = project_fixture(user)

    sheet = sheet_fixture(project)
    _block = block_fixture(sheet)
    sheet_snapshot = SheetBuilder.build_snapshot(sheet)
    sheet_block_ids = Enum.map(Sheets.list_blocks(sheet.id), & &1.id)

    flow = flow_fixture(project)
    _node = node_fixture(flow)
    flow_snapshot = FlowBuilder.build_snapshot(flow)
    flow_node_ids = Enum.map(Flows.list_nodes(flow.id), & &1.id)

    scene = scene_fixture(project)
    _layer = layer_fixture(scene)
    scene_snapshot = SceneBuilder.build_snapshot(scene)
    scene_layer_ids = Enum.map(Scenes.list_layers(scene.id), & &1.id)

    base = [
      sheet_version_restore: true,
      flow_version_restore: true,
      scene_version_restore: true,
      project_snapshot_restore: true,
      deleted_project_recovery: false
    ]

    for {entity_key, builder, entity, snapshot} <- [
          {:sheet_version_restore, SheetBuilder, sheet, sheet_snapshot},
          {:flow_version_restore, FlowBuilder, flow, flow_snapshot},
          {:scene_version_restore, SceneBuilder, scene, scene_snapshot}
        ] do
      Application.put_env(
        :storyarn,
        RestorePolicy,
        Keyword.put(base, entity_key, false)
      )

      assert {:error, :restore_temporarily_disabled} =
               builder.restore_snapshot(
                 entity,
                 snapshot,
                 restore_action: :project_snapshot_restore
               )
    end

    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == sheet_block_ids
    assert Enum.map(Flows.list_nodes(flow.id), & &1.id) == flow_node_ids
    assert Enum.map(Scenes.list_layers(scene.id), & &1.id) == scene_layer_ids
  end

  test "non-template project recovery is blocked at the materialization boundary" do
    user = user_fixture()
    project = project_fixture(user)

    policy =
      Application.get_env(:storyarn, RestorePolicy, [])

    Application.put_env(
      :storyarn,
      RestorePolicy,
      Keyword.put(policy, :deleted_project_recovery, false)
    )

    project_count = Storyarn.Repo.aggregate(Projects.Project, :count)

    assert {:error, :restore_temporarily_disabled} =
             ProjectRecovery.recover_project(
               project.workspace_id,
               %{},
               user.id
             )

    assert Storyarn.Repo.aggregate(Projects.Project, :count) == project_count
  end
end
