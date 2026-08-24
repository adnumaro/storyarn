defmodule Storyarn.Projects.Versioning.WorkspaceSnapshotReferencedTombstonesIntegrationTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshotArchiveReader
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Projects.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Projects.Workers.ImportProjectSnapshotWorker
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @type_rank %{"sheet" => 0, "flow" => 1, "scene" => 2, "block" => 3, "flow_node" => 4}
  @entry_keys ~w(deleted_at entity_type id owner snapshot)

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace, name: "Referenced tombstones source"})

    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    %{user: user, scope: user_scope_fixture(user), workspace: workspace, project: project}
  end

  test "standalone ZIP restores every active FK and keeps referenced tombstones restorable", context do
    graph = referenced_graph!(context.project)
    unrelated = unrelated_trash!(context.project, graph)
    active_bytes = "active snapshot asset"
    active_asset = upload_asset!(context.project, context.user, "active-snapshot.png", active_bytes)
    trashed_asset = upload_asset!(context.project, context.user, "trashed-snapshot.png", "trash")
    assert {:ok, _trashed} = Assets.move_asset_to_trash(context.project.id, trashed_asset.id, context.user.id)

    snapshot = build_ready_snapshot!(context.scope, context.project)
    assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)
    archive_path = temporary_archive_path!(archive)

    assert {:ok, capture} =
             ProjectSnapshotArchiveReader.verify_archive(%{
               archive_storage_key: snapshot.archive_storage_key,
               archive_size_bytes: snapshot.archive_size_bytes,
               archive_checksum: snapshot.archive_checksum
             })

    assert_capture_contract(capture, graph, unrelated, active_asset, trashed_asset)

    source_project_id = context.project.id
    original_keys = source_storage_keys(snapshot, [active_asset, trashed_asset])
    assert {:ok, deleted} = Projects.delete_project(context.project, context.user.id)
    assert {:ok, _project} = Projects.permanently_delete_project(deleted)
    refute Repo.get(Project, source_project_id)
    Enum.each(original_keys, fn key -> Storage.adapter().delete(key) end)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "referenced-tombstones.zip"}
             )

    on_exit(fn -> Storage.adapter().delete(accepted.archive_storage_key) end)
    assert :ok = accepted |> import_job!() |> ImportProjectSnapshotWorker.perform()

    completed = Repo.get!(WorkspaceSnapshotImport, accepted.id)

    assert %{status: "completed", failure_code: nil, failure_details: %{}, project_id: project_id} = completed
    assert is_integer(project_id)

    recovered = Repo.get!(Project, completed.project_id)
    assert recovered.id != source_project_id

    recovered_graph = recovered_graph!(recovered.id)

    for {label, source, field, target, original_target} <- reference_matrix(graph, recovered_graph) do
      assert Map.fetch!(source, field) == target.id, "#{label} was not remapped to its tombstone"
      assert target.deleted_at, "#{label} target was restored as active"
      assert target.deleted_at == original_target.deleted_at, "#{label} changed its deletion timestamp"
      refute target.id == original_target.id, "#{label} retained its source-project identity"
    end

    assert Enum.all?(
             [recovered_graph.flow_scene_source, recovered_graph.block_source, recovered_graph.scene_child],
             &is_nil(&1.deleted_at)
           )

    assert is_nil(recovered_graph.localized_text.archived_at)
    assert_unrelated_trash_absent(recovered.id)

    assert recovered_graph.block_target.value["target_id"] == recovered_graph.authored_sheet_target.id
    assert recovered_graph.source_node_target.data["speaker_sheet_id"] == recovered_graph.authored_sheet_target.id
    refute recovered_graph.authored_sheet_target.id == graph.authored_sheet_target.id

    assert {:ok, restored_block} = Sheets.restore_block(recovered_graph.block_target)
    assert restored_block.value["target_id"] == recovered_graph.authored_sheet_target.id

    assert {:ok, restored_node} =
             Flows.restore_node(recovered_graph.connection_flow.id, recovered_graph.source_node_target.id)

    assert restored_node.data["speaker_sheet_id"] == recovered_graph.authored_sheet_target.id

    assert [recovered_asset] = Assets.list_assets(recovered.id)
    assert recovered_asset.filename == active_asset.filename
    assert {:ok, ^active_bytes} = Storage.download(recovered_asset.key)

    refute Repo.exists?(
             from asset in Asset, where: asset.project_id == ^recovered.id and asset.filename == ^trashed_asset.filename
           )

    on_exit(fn ->
      Storage.adapter().delete(recovered_asset.key)
      Storage.adapter().delete(protected_blob_key(recovered_asset))
    end)
  end

  defp referenced_graph!(project) do
    flow_scene_target = scene_fixture(project, %{name: "tombstone-flow-scene"})

    _flow_scene_source =
      flow_fixture(project, %{name: "active-flow-scene-source", scene_id: flow_scene_target.id})

    authored_sheet_target = sheet_fixture(project, %{name: "active-authored-reference-target"})
    block_owner = sheet_fixture(project, %{name: "active-block-owner"})

    block_target =
      block_fixture(block_owner, %{
        type: "reference",
        config: %{"label" => "Tombstone reference", "allowed_types" => ["sheet", "flow"]},
        value: %{"target_type" => "sheet", "target_id" => authored_sheet_target.id}
      })

    _block_source =
      block_fixture(block_owner, %{
        variable_name: "active_block_source",
        inherited_from_block_id: block_target.id,
        detached: true
      })

    connection_flow = flow_fixture(project, %{name: "active-connection-owner"})

    source_node_target =
      node_fixture(connection_flow, %{
        data:
          "tombstone-source-node"
          |> node_data()
          |> Map.put("speaker_sheet_id", authored_sheet_target.id)
      })

    target_node_target = node_fixture(connection_flow, %{data: node_data("tombstone-target-node")})
    _connection = Storyarn.FlowsFixtures.connection_fixture(connection_flow, source_node_target, target_node_target)

    scene_parent = scene_fixture(project, %{name: "tombstone-scene-parent"})
    scene_child = scene_fixture(project, %{name: "active-scene-child", parent_id: scene_parent.id})

    pin_sheet_target = sheet_fixture(project, %{name: "tombstone-pin-sheet"})
    shared_flow_target = flow_fixture(project, %{name: "tombstone-shared-flow"})
    scene_host = scene_fixture(project, %{name: "active-scene-reference-host"})

    _pin =
      pin_fixture(scene_host, %{
        "label" => "active-reference-pin",
        "sheet_id" => pin_sheet_target.id,
        "flow_id" => shared_flow_target.id
      })

    assert {:ok, _ambient_flow} = Scenes.create_ambient_flow(scene_host.id, %{"flow_id" => shared_flow_target.id})

    speaker_sheet_target = sheet_fixture(project, %{name: "tombstone-speaker-sheet"})
    localization_flow = flow_fixture(project, %{name: "active-localization-owner"})

    localization_node =
      node_fixture(localization_flow, %{
        data: Map.put(node_data("active-localized-source"), "speaker_sheet_id", speaker_sheet_target.id)
      })

    localized_text =
      Enum.find(
        Localization.get_texts_for_source("flow_node", localization_node.id),
        &(&1.source_field == "text" and &1.locale_code == "es")
      )

    assert localized_text.speaker_sheet_id == speaker_sheet_target.id

    assert {:ok, flow_scene_target} = Scenes.delete_scene(flow_scene_target)
    assert {:ok, block_target} = Sheets.delete_block(block_target)
    assert {:ok, source_node_target, _} = Flows.delete_node(source_node_target)
    assert {:ok, target_node_target, _} = Flows.delete_node(target_node_target)
    assert {:ok, scene_parent} = Scenes.delete_scene(scene_parent)
    assert {:ok, _} = Scenes.restore_scene(scene_child)
    assert {:ok, pin_sheet_target} = Sheets.delete_sheet(pin_sheet_target)
    assert {:ok, shared_flow_target} = Flows.delete_flow(shared_flow_target)
    assert {:ok, speaker_sheet_target} = Sheets.delete_sheet(speaker_sheet_target)

    %{
      flow_scene_target: flow_scene_target,
      authored_sheet_target: authored_sheet_target,
      block_owner: block_owner,
      block_target: block_target,
      connection_flow: connection_flow,
      source_node_target: source_node_target,
      target_node_target: target_node_target,
      scene_parent: scene_parent,
      pin_sheet_target: pin_sheet_target,
      shared_flow_target: shared_flow_target,
      speaker_sheet_target: speaker_sheet_target,
      targets: [
        {"scene", flow_scene_target, %{"entity_type" => "project"}},
        {"block", block_target, %{"entity_type" => "sheet", "id" => block_owner.id}},
        {"flow_node", source_node_target, %{"entity_type" => "flow", "id" => connection_flow.id}},
        {"flow_node", target_node_target, %{"entity_type" => "flow", "id" => connection_flow.id}},
        {"scene", scene_parent, %{"entity_type" => "project"}},
        {"sheet", pin_sheet_target, %{"entity_type" => "project"}},
        {"flow", shared_flow_target, %{"entity_type" => "project"}},
        {"sheet", speaker_sheet_target, %{"entity_type" => "project"}}
      ]
    }
  end

  defp unrelated_trash!(project, graph) do
    scene = scene_fixture(project, %{name: "unrelated-trashed-scene"})
    sheet = sheet_fixture(project, %{name: "unrelated-trashed-sheet"})
    flow = flow_fixture(project, %{name: "unrelated-trashed-flow"})
    block = block_fixture(graph.block_owner, %{variable_name: "unrelated_trashed_block"})
    node = node_fixture(graph.connection_flow, %{data: node_data("unrelated-trashed-node")})

    assert {:ok, _} = Scenes.delete_scene(scene)
    assert {:ok, _} = Sheets.delete_sheet(sheet)
    assert {:ok, _} = Flows.delete_flow(flow)
    assert {:ok, _} = Sheets.delete_block(block)
    assert {:ok, _, _} = Flows.delete_node(node)

    [{"scene", scene}, {"sheet", sheet}, {"flow", flow}, {"block", block}, {"flow_node", node}]
  end

  defp assert_capture_contract(preflight, graph, unrelated, active_asset, trashed_asset) do
    assert %{"format_version" => 1, "entries" => entries} = preflight.project["referenced_tombstones"]
    expected = graph.targets |> Enum.map(fn {type, row, owner} -> {type, row.id, owner} end) |> canonical_targets()

    assert Enum.map(entries, &{&1["entity_type"], &1["id"], &1["owner"]}) == expected
    assert Enum.all?(entries, &(Enum.sort(Map.keys(&1)) == @entry_keys))
    assert Enum.all?(entries, &(is_binary(&1["deleted_at"]) and is_map(&1["snapshot"])))
    assert length(entries) == 8

    assert Enum.count(entries, &(&1["entity_type"] == "flow" and &1["id"] == graph.shared_flow_target.id)) == 1

    unrelated_ids = MapSet.new(unrelated, fn {type, row} -> {type, row.id} end)
    refute Enum.any?(entries, &MapSet.member?(unrelated_ids, {&1["entity_type"], &1["id"]}))

    assert Enum.map(preflight.manifest["assets"], & &1["filename"]) == [active_asset.filename]
    refute Enum.any?(preflight.manifest["assets"], &(&1["filename"] == trashed_asset.filename))
  end

  defp recovered_graph!(project_id) do
    flow_scene_source = one_by_name!(Flow, project_id, "active-flow-scene-source")
    connection_flow = one_by_name!(Flow, project_id, "active-connection-owner")
    scene_host = one_by_name!(Scene, project_id, "active-scene-reference-host")
    block_source = one_block!(project_id, "active_block_source")

    %{
      flow_scene_source: flow_scene_source,
      flow_scene_target: one_by_name!(Scene, project_id, "tombstone-flow-scene"),
      authored_sheet_target: one_by_name!(Sheet, project_id, "active-authored-reference-target"),
      block_source: block_source,
      block_target: Repo.get!(Block, block_source.inherited_from_block_id),
      connection_flow: connection_flow,
      connection: Repo.one!(from connection in FlowConnection, where: connection.flow_id == ^connection_flow.id),
      source_node_target:
        Repo.one!(
          from node in FlowNode,
            where: node.flow_id == ^connection_flow.id and node.data["text"] == "tombstone-source-node"
        ),
      target_node_target:
        Repo.one!(
          from node in FlowNode,
            where: node.flow_id == ^connection_flow.id and node.data["text"] == "tombstone-target-node"
        ),
      scene_child: one_by_name!(Scene, project_id, "active-scene-child"),
      scene_parent: one_by_name!(Scene, project_id, "tombstone-scene-parent"),
      pin: Repo.one!(from pin in ScenePin, where: pin.scene_id == ^scene_host.id),
      pin_sheet_target: one_by_name!(Sheet, project_id, "tombstone-pin-sheet"),
      shared_flow_target: one_by_name!(Flow, project_id, "tombstone-shared-flow"),
      ambient_flow: Repo.one!(from ambient in SceneAmbientFlow, where: ambient.scene_id == ^scene_host.id),
      localized_text:
        Repo.one!(
          from text in LocalizedText,
            where:
              text.project_id == ^project_id and text.source_text == "active-localized-source" and
                text.locale_code == "es"
        ),
      speaker_sheet_target: one_by_name!(Sheet, project_id, "tombstone-speaker-sheet")
    }
  end

  defp reference_matrix(old, new) do
    [
      {"flow.scene_id", new.flow_scene_source, :scene_id, new.flow_scene_target, old.flow_scene_target},
      {"block.inherited_from_block_id", new.block_source, :inherited_from_block_id, new.block_target, old.block_target},
      {"flow_connection.source_node_id", new.connection, :source_node_id, new.source_node_target, old.source_node_target},
      {"flow_connection.target_node_id", new.connection, :target_node_id, new.target_node_target, old.target_node_target},
      {"scene.parent_id", new.scene_child, :parent_id, new.scene_parent, old.scene_parent},
      {"scene_pin.sheet_id", new.pin, :sheet_id, new.pin_sheet_target, old.pin_sheet_target},
      {"scene_pin.flow_id", new.pin, :flow_id, new.shared_flow_target, old.shared_flow_target},
      {"scene_ambient_flow.flow_id", new.ambient_flow, :flow_id, new.shared_flow_target, old.shared_flow_target},
      {"localized_text.speaker_sheet_id", new.localized_text, :speaker_sheet_id, new.speaker_sheet_target,
       old.speaker_sheet_target}
    ]
  end

  defp assert_unrelated_trash_absent(project_id) do
    refute Repo.exists?(from row in Scene, where: row.project_id == ^project_id and row.name == "unrelated-trashed-scene")
    refute Repo.exists?(from row in Sheet, where: row.project_id == ^project_id and row.name == "unrelated-trashed-sheet")
    refute Repo.exists?(from row in Flow, where: row.project_id == ^project_id and row.name == "unrelated-trashed-flow")
    refute Repo.exists?(from row in Block, where: row.variable_name == "unrelated_trashed_block")
    refute Repo.exists?(from row in FlowNode, where: row.data["text"] == "unrelated-trashed-node")
  end

  defp one_by_name!(schema, project_id, name),
    do: Repo.one!(from entity in schema, where: entity.project_id == ^project_id and entity.name == ^name)

  defp one_block!(project_id, variable_name),
    do:
      Repo.one!(
        from block in Block,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where: sheet.project_id == ^project_id and block.variable_name == ^variable_name
      )

  defp canonical_targets(targets), do: Enum.sort_by(targets, fn {type, id, _owner} -> {@type_rank[type], id} end)
  defp node_data(text), do: %{"speaker" => "Narrator", "text" => text}

  defp build_ready_snapshot!(scope, project) do
    assert {:ok, requested} =
             Versioning.request_full_project_snapshot(scope, project, %{idempotency_key: Ecto.UUID.generate()})

    job =
      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(state: "executing", attempt: 1, attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}})
      |> Repo.update!()

    assert :ok = BuildProjectSnapshotWorker.perform(job)
    Versioning.get_project_snapshot(project.id, requested.id)
  end

  defp import_job!(operation) do
    operation.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Map.put(:attempt, 1)
    |> Map.put(:max_attempts, ImportProjectSnapshotWorker.max_attempts())
  end

  defp upload_asset!(project, user, filename, bytes) do
    assert {:ok, asset} =
             Assets.upload_binary_and_create_asset(bytes, %{filename: filename, content_type: "image/png"}, project, user)

    on_exit(fn ->
      Storage.adapter().delete(asset.key)
      Storage.adapter().delete(protected_blob_key(asset))
    end)

    asset
  end

  defp source_storage_keys(snapshot, assets) do
    [snapshot.archive_storage_key, snapshot.manifest_storage_key] ++
      Enum.flat_map(assets, &[&1.key, protected_blob_key(&1)])
  end

  defp protected_blob_key(asset),
    do: BlobStore.blob_key(asset.project_id, asset.blob_hash, BlobStore.ext_from_content_type(asset.content_type))

  defp temporary_archive_path!(archive) do
    path = Path.join(System.tmp_dir!(), "storyarn-tombstones-#{Ecto.UUID.generate()}.zip")
    File.write!(path, archive, [:binary])
    on_exit(fn -> File.rm(path) end)
    path
  end
end
