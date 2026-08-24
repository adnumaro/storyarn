defmodule Storyarn.Imports.ReplacementRestoreIntegrationTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets.Storage.Local
  alias Storyarn.Imports
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotRestore
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.RestoreProjectSnapshotWorker

  test "a real pre-import snapshot restores the graph replaced by a Yarn project import" do
    user = user_fixture()
    project = project_fixture(user)
    scope = Scope.for_user(user)
    on_exit(fn -> delete_project_storage(project.id) end)

    original_sheet = sheet_fixture(project, %{name: "Recovery Character"})
    original_child = child_sheet_fixture(project, original_sheet, %{name: "Recovery Character Notes"})
    _original_block = block_fixture(original_child, %{value: %{"content" => "Recover this note"}})

    original_flow = flow_fixture(project, %{name: "Recovery Quest"})
    first_node = node_fixture(original_flow, %{data: %{"speaker" => "Guide", "text" => "The old quest begins."}})
    second_node = node_fixture(original_flow, %{data: %{"speaker" => "Guide", "text" => "The old quest ends."}})

    _original_connection =
      Storyarn.FlowsFixtures.connection_fixture(original_flow, first_node, second_node)

    original_node_count =
      Repo.aggregate(from(node in FlowNode, where: node.flow_id == ^original_flow.id), :count)

    original_connection_count =
      Repo.aggregate(
        from(connection in FlowConnection, where: connection.flow_id == ^original_flow.id),
        :count
      )

    original_scene = scene_fixture(project, %{name: "Recovery Village"})
    _original_layer = layer_fixture(original_scene, %{"name" => "Recovery Foreground"})
    _original_pin = pin_fixture(original_scene, %{"label" => "Recovery Gate"})

    assert {:ok, _original_asset} =
             Storyarn.Assets.upload_binary_and_create_asset(
               "recoverable map bytes",
               %{filename: "recovery-map.png", content_type: "image/png"},
               project,
               user
             )

    assert {:ok, ready, _preview} =
             Imports.prepare_import(
               scope,
               project,
               "replacement-project.zip",
               replaceable_yarn_archive()
             )

    assert ready.replace_eligible
    assert {:ok, ready} = Imports.update_import_mode(scope, ready.id, "replace_project")

    assert {:ok, queued} =
             Imports.enqueue_import(scope, ready.id, :rename,
               import_mode: "replace_project",
               replace_acknowledged: true
             )

    assert {:snooze, 5} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    snapshot = Repo.get!(ProjectSnapshot, waiting.pre_import_snapshot_id)
    assert snapshot.lifecycle_state == "pending"

    snapshot_job = mark_job_executing!(snapshot.build_job_id)
    assert :ok = BuildProjectSnapshotWorker.perform(snapshot_job)

    snapshot = Repo.get!(ProjectSnapshot, snapshot.id)
    assert snapshot.lifecycle_state == "ready"
    assert snapshot.integrity_state == "verified"
    assert snapshot.restore_contract_version == 1

    assert {:ok, completed_import} =
             Imports.perform_import(waiting.id, attempt: 1, max_attempts: 3)

    assert completed_import.status == "completed"
    assert Repo.get!(Sheet, original_sheet.id).deleted_at
    assert Repo.get!(Sheet, original_child.id).deleted_at
    assert Repo.get!(Flow, original_flow.id).deleted_at
    assert Repo.get!(Scene, original_scene.id).deleted_at
    assert active_flow_names(project.id) == ["Start"]

    assert {:ok, requested_restore} =
             Versioning.request_project_snapshot_restore(scope, project, snapshot, %{
               idempotency_key: Ecto.UUID.generate()
             })

    restore_job = mark_job_executing!(requested_restore.oban_job_id)
    restore_result = RestoreProjectSnapshotWorker.perform(restore_job)
    restored_operation = Repo.get!(ProjectSnapshotRestore, requested_restore.id)
    assert restore_result == :ok, restore_failure_message(restored_operation)
    assert restored_operation.status == "completed"

    restored_sheet = active_sheet!(project.id, "Recovery Character")
    restored_child = active_sheet!(project.id, "Recovery Character Notes")
    assert restored_sheet.id != original_sheet.id
    assert restored_child.id != original_child.id
    assert restored_child.parent_id == restored_sheet.id

    assert Repo.aggregate(
             from(block in Block,
               where: block.sheet_id == ^restored_child.id and is_nil(block.deleted_at)
             ),
             :count
           ) == 1

    restored_flow = active_flow!(project.id, "Recovery Quest")
    assert restored_flow.id != original_flow.id
    assert active_flow_names(project.id) == ["Recovery Quest"]

    assert Repo.aggregate(from(node in FlowNode, where: node.flow_id == ^restored_flow.id), :count) ==
             original_node_count

    assert Repo.aggregate(
             from(connection in FlowConnection, where: connection.flow_id == ^restored_flow.id),
             :count
           ) == original_connection_count

    restored_scene = active_scene!(project.id, "Recovery Village")
    assert restored_scene.id != original_scene.id

    assert Repo.exists?(
             from(layer in SceneLayer,
               where: layer.scene_id == ^restored_scene.id and layer.name == "Recovery Foreground"
             )
           )

    assert Repo.exists?(from(pin in ScenePin, where: pin.scene_id == ^restored_scene.id and pin.label == "Recovery Gate"))

    refute Repo.exists?(
             from(flow in Flow,
               where: flow.project_id == ^project.id and flow.name == "Start" and is_nil(flow.deleted_at)
             )
           )
  end

  defp mark_job_executing!(job_id) do
    job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: 1,
      attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
    )
    |> Repo.update!()
  end

  defp restore_failure_message(restore) do
    "restore failed with status=#{restore.status} phase=#{restore.phase} " <>
      "code=#{inspect(restore.failure_code)} details=#{inspect(restore.failure_details)}"
  end

  defp active_sheet!(project_id, name) do
    Repo.one!(
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id and sheet.name == ^name and is_nil(sheet.deleted_at)
      )
    )
  end

  defp active_flow!(project_id, name) do
    Repo.one!(
      from(flow in Flow,
        where: flow.project_id == ^project_id and flow.name == ^name and is_nil(flow.deleted_at)
      )
    )
  end

  defp active_scene!(project_id, name) do
    Repo.one!(
      from(scene in Scene,
        where: scene.project_id == ^project_id and scene.name == ^name and is_nil(scene.deleted_at)
      )
    )
  end

  defp active_flow_names(project_id) do
    Repo.all(
      from(flow in Flow,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        order_by: [asc: flow.name],
        select: flow.name
      )
    )
  end

  defp replaceable_yarn_archive do
    project =
      Jason.encode!(%{
        "projectFileVersion" => 3,
        "sourceFiles" => ["*.yarn"],
        "excludeFiles" => []
      })

    entries = [
      {~c"project.yarnproject", project},
      {~c"main.yarn", "title: Start\n---\nA temporary imported quest.\n===\n"}
    ]

    {:ok, {_name, binary}} = :zip.create(~c"replacement-project.zip", entries, [:memory])
    binary
  end

  defp delete_project_storage(project_id) do
    {:ok, %{objects: objects, cursor: nil}} =
      Local.list_prefix("projects/#{project_id}/", limit: 10_000)

    Enum.each(objects, &Local.delete(&1.key))
  end
end
