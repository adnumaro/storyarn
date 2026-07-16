defmodule Storyarn.ProjectTemplates.AuditSequenceTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "Outer"})
    {:ok, inner} = Flows.create_sequence(flow.id, %{"name" => "Inner", "parent_id" => outer.id})
    _child = node_fixture(flow, %{type: "hub", parent_id: inner.id})

    {:ok, _track} =
      Flows.upsert_sequence_track(inner.id, "music", %{"volume" => Decimal.new("0.5")})

    %{user: user, project: project, flow: flow, outer: outer, inner: inner}
  end

  test "audits sequence resources and parent links through materialization", %{project: project} do
    assert {:ok, report, snapshot} = Audit.run_with_snapshot(project.id)

    assert report["status"] == "passed"

    assert %{
             "flow_node_parent_links" => 2,
             "sequence_configs" => 2,
             "sequence_tracks" => 1,
             "sequence_visual_layers" => 0
           } = report["entity_counts"]

    assert report["materialization"]["source_counts"]["flow_node_parent_links"] == 2
    assert report["materialization"]["snapshot_counts"]["sequence_configs"] == 2
    assert report["materialization"]["recovered_counts"]["sequence_tracks"] == 1

    [flow_entry] = snapshot["flows"]
    sequence_snapshots = Enum.filter(flow_entry["snapshot"]["nodes"], &(&1["type"] == "sequence"))
    assert Enum.all?(sequence_snapshots, &is_map(&1["sequence_config"]))
  end

  test "rejects a template snapshot whose sequence config is missing", %{
    user: user,
    project: project,
    inner: inner
  } do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    snapshot =
      update_in(snapshot, ["flows", Access.all(), "snapshot", "nodes", Access.all()], fn node ->
        if node["original_id"] == inner.id, do: Map.put(node, "sequence_config", nil), else: node
      end)

    assert {:error, report} =
             Audit.verify_snapshot_materialization(snapshot, project.workspace_id, user.id)

    assert report["status"] == "failed"

    assert Enum.any?(report["errors"], fn error ->
             error["type"] == "missing_sequence_config_snapshot" and error["node_id"] == inner.id
           end)
  end

  test "reports malformed sequence collection items", %{user: user, project: project, inner: inner} do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    snapshot =
      update_in(snapshot, ["flows", Access.all(), "snapshot", "nodes", Access.all()], fn node ->
        if node["original_id"] == inner.id,
          do: Map.put(node, "sequence_tracks", ["not-a-track"]),
          else: node
      end)

    assert {:error, report} =
             Audit.verify_snapshot_materialization(snapshot, project.workspace_id, user.id)

    assert Enum.any?(report["errors"], fn error ->
             error["type"] == "invalid_sequence_collection_item_snapshot" and
               error["field"] == "sequence_tracks"
           end)
  end

  test "rejects sequence snapshots that omit resource collections", %{
    project: project,
    inner: inner
  } do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    snapshot =
      update_in(snapshot, ["flows", Access.all(), "snapshot", "nodes", Access.all()], fn node ->
        if node["original_id"] == inner.id,
          do: Map.delete(node, "sequence_tracks"),
          else: node
      end)

    assert {:error, errors} = Audit.validate_snapshot_integrity(snapshot)

    assert Enum.any?(errors, fn error ->
             error["type"] == "missing_sequence_collection_snapshot" and
               error["node_id"] == inner.id and
               error["field"] == "sequence_tracks"
           end)
  end
end
