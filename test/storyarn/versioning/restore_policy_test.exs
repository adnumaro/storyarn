defmodule Storyarn.Versioning.RestorePolicyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.VersionCrud

  setup do
    original_config = Application.get_env(:storyarn, RestorePolicy)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, original_config)
      end
    end)

    :ok
  end

  test "exact full-project restore is always available independently of entity switches" do
    Application.put_env(:storyarn, RestorePolicy,
      sheet_version_restore: false,
      flow_version_restore: false,
      scene_version_restore: false
    )

    assert RestorePolicy.enabled?({:project_snapshot_restore, "full"})
    assert :ok = RestorePolicy.ensure_enabled({:project_snapshot_restore, "full"})
  end

  test "missing, unknown, and non-boolean entity configuration values fail closed" do
    Application.delete_env(:storyarn, RestorePolicy)

    refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?({:entity_version_restore, "unknown"})
    refute RestorePolicy.enabled?(:unknown_action)

    Application.put_env(:storyarn, RestorePolicy,
      sheet_version_restore: "true",
      flow_version_restore: 1,
      scene_version_restore: nil
    )

    refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?({:entity_version_restore, "flow"})
    refute RestorePolicy.enabled?({:entity_version_restore, "scene"})

    for invalid_config <- [%{}, nil, ["invalid"]] do
      Application.put_env(:storyarn, RestorePolicy, invalid_config)
      refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    end
  end

  test "entity restore surfaces are enabled independently only by literal true" do
    Application.put_env(:storyarn, RestorePolicy,
      sheet_version_restore: true,
      flow_version_restore: false,
      scene_version_restore: false
    )

    assert RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?({:entity_version_restore, "flow"})
    refute RestorePolicy.enabled?({:entity_version_restore, "scene"})
  end

  test "the public facade rejects entity restore before mutating or creating a safety version" do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Original"})
    block = block_fixture(sheet)

    {:ok, version} =
      Versioning.create_version("sheet", sheet, project.id, user.id, title: "Restore target")

    {:ok, changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed"})

    Application.put_env(:storyarn, RestorePolicy,
      sheet_version_restore: false,
      flow_version_restore: false,
      scene_version_restore: false
    )

    assert {:error, :restore_temporarily_disabled} =
             Versioning.restore_version("sheet", changed_sheet, version, user_id: user.id)

    assert {:error, :restore_temporarily_disabled} =
             VersionCrud.restore_version("sheet", changed_sheet, version, user_id: user.id)

    assert Sheets.get_sheet(project.id, sheet.id).name == "Changed"
    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == [block.id]
    assert Versioning.count_versions("sheet", sheet.id) == 1
  end

  test "entity builders require a policy-scoped entity action" do
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

    Application.put_env(:storyarn, RestorePolicy,
      sheet_version_restore: true,
      flow_version_restore: true,
      scene_version_restore: true
    )

    for {builder, entity, snapshot} <- [
          {SheetBuilder, sheet, sheet_snapshot},
          {FlowBuilder, flow, flow_snapshot},
          {SceneBuilder, scene, scene_snapshot}
        ] do
      assert {:error, :restore_temporarily_disabled} =
               builder.restore_snapshot(entity, snapshot)

      restore_opts = [restore_action: {:entity_version_restore, entity_type(entity)}]

      assert {:ok, _restored} =
               builder.restore_snapshot(entity, snapshot, restore_opts)
    end

    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == sheet_block_ids
    assert Enum.map(Flows.list_nodes(flow.id), & &1.id) == flow_node_ids
    assert Enum.map(Scenes.list_layers(scene.id), & &1.id) == scene_layer_ids
  end

  defp entity_type(%Storyarn.Sheets.Sheet{}), do: "sheet"
  defp entity_type(%Storyarn.Flows.Flow{}), do: "flow"
  defp entity_type(%Storyarn.Scenes.Scene{}), do: "scene"
end
