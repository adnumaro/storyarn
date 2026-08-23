defmodule Storyarn.Flows.VersioningTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Versioning
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.RestorePolicy
  alias Storyarn.Repo
  alias Storyarn.Versioning, as: LegacyVersioning

  setup do
    previous_policy = Application.get_env(:storyarn, RestorePolicy)
    Application.put_env(:storyarn, RestorePolicy, flow_version_restore: true)

    on_exit(fn ->
      if is_nil(previous_policy),
        do: Application.delete_env(:storyarn, RestorePolicy),
        else: Application.put_env(:storyarn, RestorePolicy, previous_policy)
    end)

    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project, %{name: "Opening", shortcut: "opening"})

    %{user: user, project: project, flow: flow}
  end

  describe "Flow-owned version lifecycle" do
    test "creates, verifies, lists, rate-limits, names, and deletes versions", %{
      user: user,
      flow: flow
    } do
      assert {:ok, %EntityVersionRecord{} = first} =
               Versioning.create_version(flow, user.id, title: "First")

      assert first.entity_type == "flow"
      assert first.entity_id == flow.id
      assert first.project_id == flow.project_id
      assert first.version_number == 1
      assert first.checksum =~ ~r/\A[0-9a-f]{64}\z/

      assert {:ok, snapshot} = Versioning.load_version_snapshot(first)
      assert snapshot["original_id"] == flow.id
      assert snapshot["name"] == "Opening"

      assert {:skipped, :too_recent} =
               Versioning.maybe_create_version(flow, user.id, min_interval: 600)

      assert {:ok, second} =
               Versioning.maybe_create_version(flow, user.id, min_interval: 0)

      assert second.version_number == 2
      assert Enum.map(Versioning.list_versions(flow.id), & &1.id) == [second.id, first.id]
      assert Versioning.get_version(flow.id, 1).id == first.id
      assert Versioning.get_latest_version(flow.id).id == second.id
      assert Versioning.count_versions(flow.id) == 2

      assert {:ok, promoted} =
               Versioning.update_version(second, %{title: "Checkpoint", description: "Ready"})

      refute promoted.is_auto
      assert promoted.title == "Checkpoint"

      assert {:ok, deleted} = Versioning.delete_version(first)
      assert deleted.id == first.id
      assert Versioning.get_version(flow.id, 1) == nil
      assert {:error, _reason} = Versioning.load_version_snapshot(first)
    end

    test "the legacy Versioning facade no longer exposes entity versioning", %{
      user: user,
      flow: flow
    } do
      assert {:ok, created} = Versioning.create_version(flow, user.id, title: "Flow owner")

      Code.ensure_loaded!(LegacyVersioning)

      for {fun, arity} <- [
            create_version: 5,
            maybe_create_version: 5,
            list_versions: 3,
            get_version: 3,
            get_latest_version: 2,
            count_versions: 2,
            get_adjacent_version_numbers: 3,
            count_versions_since: 3,
            update_version: 2,
            count_named_versions: 1,
            delete_version: 1,
            load_version_snapshot: 1,
            restore_version: 4,
            detect_restore_conflicts: 3,
            get_builder!: 1,
            next_version_number: 2
          ] do
        refute function_exported?(LegacyVersioning, fun, arity),
               "expected the legacy facade to no longer export #{fun}/#{arity}"
      end

      assert Versioning.get_version(flow.id, created.version_number).title == "Flow owner"
    end

    test "restores root data, nodes, connections, and creates safety versions", %{
      user: user,
      flow: flow
    } do
      first = node_fixture(flow, %{type: "dialogue", position_x: 10.0, position_y: 20.0})
      second = node_fixture(flow, %{type: "hub", position_x: 30.0, position_y: 40.0})
      connection = connection_fixture(flow, first, second)

      assert {:ok, target} = Versioning.create_version(flow, user.id, title: "Original")
      assert {:ok, changed_flow} = Flows.update_flow(flow, %{name: "Changed"})
      assert {:ok, _deleted, _metadata} = Flows.delete_node(second)

      assert {:ok, restored} =
               Versioning.restore_version(changed_flow, target, user_id: user.id)

      assert restored.name == "Opening"

      active_nodes =
        Repo.all(
          from(node in FlowNode,
            where: node.flow_id == ^flow.id and is_nil(node.deleted_at),
            order_by: [asc: node.id]
          )
        )

      restored_ids = MapSet.new(active_nodes, & &1.id)
      assert MapSet.subset?(MapSet.new([first.id, second.id]), restored_ids)

      assert [%FlowConnection{source_node_id: source_id, target_node_id: target_id}] =
               Repo.all(from(current in FlowConnection, where: current.flow_id == ^flow.id))

      assert source_id == first.id
      assert target_id == second.id
      assert Repo.get!(FlowConnection, connection.id).id == connection.id

      versions = Versioning.list_versions(flow.id)
      assert length(versions) == 3
      assert Enum.any?(versions, &(&1.title == "Before restore to v1"))
      assert Enum.any?(versions, &(&1.title == "Restored from v1"))
    end

    test "rejects a version from another Flow without creating safety state", %{
      user: user,
      project: project,
      flow: flow
    } do
      other = flow_fixture(project)
      assert {:ok, other_version} = Versioning.create_version(other, user.id)

      assert {:error, :entity_version_scope_mismatch} =
               Versioning.restore_version(flow, other_version, user_id: user.id)

      assert Versioning.count_versions(flow.id) == 0
    end

    test "restore policy fails closed", %{user: user, flow: flow} do
      assert {:ok, target} = Versioning.create_version(flow, user.id)
      Application.delete_env(:storyarn, RestorePolicy)

      refute Versioning.restore_enabled?()

      assert {:error, :restore_temporarily_disabled} =
               Versioning.restore_version(flow, target, user_id: user.id)

      assert Versioning.count_versions(flow.id) == 1
    end

    test "rejects a restore when Flow changes after its verified safety version", %{
      user: user,
      flow: flow
    } do
      assert {:ok, target} = Versioning.create_version(flow, user.id)
      assert {:ok, current} = Flows.update_flow(flow, %{name: "Current"})

      hook = fn _safety_version ->
        current = Repo.get!(Flow, flow.id)
        assert {:ok, _changed} = Flows.update_flow(current, %{name: "Concurrent"})
      end

      assert {:error, :flow_changed_since_pre_restore_snapshot} =
               Versioning.restore_version(current, target,
                 user_id: user.id,
                 __after_pre_restore_version_verified_hook: hook
               )

      assert Repo.get!(Flow, flow.id).name == "Concurrent"
      assert Versioning.count_versions(flow.id) == 2
      refute Enum.any?(Versioning.list_versions(flow.id), &String.starts_with?(&1.title || "", "Restored from"))
    end

    test "fails closed for malformed or non-durable safety-version identity", %{
      user: user,
      flow: flow
    } do
      target_snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, current} = Flows.update_flow(flow, %{name: "Current state"})
      pre_restore_snapshot = FlowSnapshot.build_snapshot(current)
      assert {:ok, safety_version} = Versioning.create_version(current, user.id)

      assert {:error, :invalid_pre_restore_version_identity} =
               FlowSnapshot.restore_snapshot(current, target_snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 user_id: user.id,
                 pre_restore_snapshot: pre_restore_snapshot,
                 pre_restore_version_identity: %{}
               )

      assert Repo.get!(Flow, flow.id).name == "Current state"

      identity = version_identity(safety_version)
      assert {:ok, _deleted} = Versioning.delete_version(safety_version)

      assert {:error, :pre_restore_version_not_durable} =
               FlowSnapshot.restore_snapshot(current, target_snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 user_id: user.id,
                 pre_restore_snapshot: pre_restore_snapshot,
                 pre_restore_version_identity: identity
               )

      assert Repo.get!(Flow, flow.id).name == "Current state"
    end

    test "validates localization manifest before mutating Flow state", %{flow: flow} do
      _node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Historical", "responses" => []}})
      snapshot = FlowSnapshot.build_snapshot(flow)
      corrupted = put_in(snapshot, ["localization_manifest", "sha256"], String.duplicate("0", 64))

      assert {:error, {:localization_manifest_mismatch, _actual, _expected}} =
               FlowSnapshot.restore_snapshot(flow, corrupted, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(Flow, flow.id).name == flow.name
    end

    test "restores safely when the version actor is nil", %{flow: flow} do
      assert {:ok, target} = Versioning.create_version(flow, nil)
      assert {:ok, changed} = Flows.update_flow(flow, %{name: "Changed without actor"})

      assert {:ok, restored} = Versioning.restore_version(changed, target, user_id: nil)
      assert restored.name == flow.name

      versions = Versioning.list_versions(flow.id)
      assert length(versions) == 2
      assert Enum.any?(versions, &(&1.title == "Before restore to v1" and is_nil(&1.created_by_id)))
    end

    test "previews missing references and shortcut collisions with Flow-owned records", %{
      project: project,
      flow: flow
    } do
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Reference", "responses" => []}})
      snapshot = FlowSnapshot.build_snapshot(flow)
      other = flow_fixture(project)

      snapshot =
        snapshot
        |> Map.put("shortcut", other.shortcut)
        |> Map.update!("nodes", fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => id} = current when id == node.id ->
              put_in(current, ["data", "speaker_sheet_id"], 9_999_999)

            current ->
              current
          end)
        end)

      report = Versioning.detect_restore_conflicts(snapshot, flow)

      assert report.has_conflicts
      assert report.shortcut_collision
      assert report.resolved_shortcut == other.shortcut <> "-restored"
      assert Enum.any?(report.conflicts, &(&1.type == :sheet and &1.id == 9_999_999))
    end
  end

  describe "named version capacity" do
    test "blocks a new named version when the project is at the limit", %{
      user: user,
      project: project,
      flow: flow
    } do
      seed_named_versions(flow, 10)

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Flows.create_version(flow, user.id, title: "Over the limit", skip_diff: true)

      assert Flows.count_versions(flow.id) == 10

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Flows.can_create_named_version?(project.id, project.workspace_id)
    end

    test "allows an automatic version when the named-version limit is full", %{
      user: user,
      project: project,
      flow: flow
    } do
      seed_named_versions(flow, 10)

      assert {:ok, %EntityVersionRecord{} = automatic} =
               Flows.maybe_create_version(flow, user.id,
                 min_interval: 0,
                 skip_diff: true
               )

      assert automatic.is_auto
      assert is_nil(automatic.title)
      assert Flows.count_versions(flow.id) == 11

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Flows.can_create_named_version?(project.id, project.workspace_id)
    end

    test "blocks promotion of an automatic version when the project is at the limit", %{
      project: project,
      flow: flow
    } do
      seed_named_versions(flow, 10)
      automatic = insert_version!(flow, 11, %{is_auto: true, title: nil})

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Flows.update_version(automatic, %{title: "Blocked promotion"})

      persisted = Flows.get_version(flow.id, automatic.version_number)
      assert persisted.is_auto
      assert is_nil(persisted.title)
      assert named_version_count(project.id) == 10
    end

    test "allows editing an existing named version when the project is at the limit", %{
      project: project,
      flow: flow
    } do
      [existing | _versions] = seed_named_versions(flow, 10)

      assert {:ok, %EntityVersionRecord{} = updated} =
               Flows.update_version(existing, %{
                 title: "Renamed checkpoint",
                 description: "Still occupies the same quota slot"
               })

      assert updated.title == "Renamed checkpoint"
      assert updated.description == "Still occupies the same quota slot"
      refute updated.is_auto
      assert named_version_count(project.id) == 10
    end
  end

  defp seed_named_versions(flow, count) do
    Enum.map(1..count, fn version_number ->
      insert_version!(flow, version_number, %{title: "Checkpoint #{version_number}"})
    end)
  end

  defp insert_version!(flow, version_number, attrs) do
    base_attrs = %{
      entity_type: "flow",
      entity_id: flow.id,
      project_id: flow.project_id,
      version_number: version_number,
      title: nil,
      description: nil,
      storage_key: "projects/#{flow.project_id}/snapshots/flow/#{flow.id}/test-#{version_number}.json.gz",
      snapshot_size_bytes: 0,
      checksum: String.duplicate("a", 64),
      is_auto: false
    }

    %EntityVersionRecord{}
    |> EntityVersionRecord.create_changeset(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp named_version_count(project_id) do
    Repo.aggregate(
      from(version in EntityVersionRecord,
        where:
          version.project_id == ^project_id and not is_nil(version.title) and
            version.is_auto == false
      ),
      :count
    )
  end

  defp version_identity(%EntityVersionRecord{} = version) do
    %{
      id: version.id,
      entity_type: version.entity_type,
      entity_id: version.entity_id,
      project_id: version.project_id,
      created_by_id: version.created_by_id,
      version_number: version.version_number,
      storage_key: version.storage_key,
      snapshot_size_bytes: version.snapshot_size_bytes,
      checksum: version.checksum
    }
  end
end
