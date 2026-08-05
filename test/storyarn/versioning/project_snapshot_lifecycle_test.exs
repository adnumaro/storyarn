defmodule Storyarn.Versioning.ProjectSnapshotLifecycleTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Projects
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.ProjectSnapshotRetentionWorker
  alias Storyarn.Workspaces

  describe "delete_project_snapshot/3" do
    test "records exact immutable ownership before dropping quota and cleans idempotently" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      expected_bytes = ready.accounted_size_bytes

      assert Billing.workspace_storage_usage(project.workspace_id).full_snapshots == %{
               bytes: expected_bytes,
               count: 1
             }

      assert {:ok, intent} =
               Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      refute Repo.get(ProjectSnapshot, ready.id)
      assert intent.project_snapshot_id_snapshot == ready.id
      assert intent.deletion_generation == ready.lifecycle_generation + 1
      assert intent.reason == "user_delete"
      assert intent.authority_kind == "user"
      assert intent.authority_actor_id == user.id
      assert intent.storage_keys == Enum.uniq(intent.storage_keys)
      assert intent.object_count == length(intent.storage_keys)
      assert ready.manifest_storage_key in intent.storage_keys
      assert ready.project_storage_key in intent.storage_keys
      assert Enum.any?(intent.storage_keys, &String.contains?(&1, "/staging/"))
      assert Billing.workspace_storage_usage(project.workspace_id).full_snapshots == %{bytes: 0, count: 0}

      assert {:ok, :completed} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
      assert {:error, _reason} = Storage.stat(ready.manifest_storage_key)
      assert {:error, _reason} = Storage.stat(ready.project_storage_key)
      assert {:ok, :already_completed} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
    end

    test "rejects an actor without project management authority" do
      owner = user_fixture()
      outsider = user_fixture()
      project = project_fixture(owner)
      ready = create_ready_snapshot(owner, project)

      assert {:error, :unauthorized} =
               Versioning.delete_project_snapshot(user_scope_fixture(outsider), project, ready.id)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "checkpoints partial provider success and retries only the remaining inventory" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)
      failed_key = ready.manifest_storage_key

      delete_with_one_failure = fn keys ->
        successful = Enum.reject(keys, &(&1 == failed_key))
        assert :ok = StorageCompensation.delete_storage_keys(successful)
        {:error, [failed_key]}
      end

      assert {:error, :storage_provider_failure} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: delete_with_one_failure
               )

      retrying = Repo.get!(SnapshotCleanupIntent, intent.id)
      assert retrying.status == "retrying"
      assert retrying.remaining_storage_keys == [failed_key]
      assert retrying.retry_count == 1

      assert {:ok, :completed} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
      assert Repo.get!(SnapshotCleanupIntent, intent.id).remaining_storage_keys == []
    end

    test "preserves a terminal failure inventory for operator recovery" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fn keys -> {:error, keys} end,
                 final_attempt?: true
               )

      terminal = Repo.get!(SnapshotCleanupIntent, intent.id)
      assert terminal.status == "terminal"
      assert terminal.remaining_storage_keys == intent.storage_keys
      assert terminal.terminal_at
      assert Versioning.project_snapshot_cleanup_backlog().terminal_failures == 1
    end
  end

  describe "retention" do
    test "revalidates every candidate fact under lock before deletion" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      now = TimeHelpers.now()
      expires_at = DateTime.add(now, -60, :second)

      ready
      |> Ecto.Changeset.change(origin: "daily", expires_at: expires_at)
      |> Repo.update!()

      assert [candidate] = Versioning.list_project_snapshot_retention_candidates(now)

      ProjectSnapshot
      |> Repo.get!(ready.id)
      |> Ecto.Changeset.change(expires_at: DateTime.add(now, 3_600, :second))
      |> Repo.update!()

      assert {:error, :retention_candidate_changed} =
               Versioning.delete_project_snapshot_retention_candidate(candidate, now)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "daily worker deletes through the lifecycle context and reports its batch" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)

      ready
      |> Ecto.Changeset.change(
        origin: "daily",
        expires_at: DateTime.add(TimeHelpers.now(), -60, :second)
      )
      |> Repo.update!()

      handler_id = "snapshot-retention-test-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :retention, :stop],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = ProjectSnapshotRetentionWorker.perform(%Oban.Job{args: %{}})
      refute Repo.get(ProjectSnapshot, ready.id)

      assert %SnapshotCleanupIntent{reason: "retention"} =
               Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: ready.id)

      assert_receive {
        [:storyarn, :snapshot, :retention, :stop],
        %{deleted_count: 1, failure_count: 0},
        %{status: :ok}
      }
    end
  end

  describe "expired builds" do
    test "requires both reservation expiry and a terminal owning job before cleanup" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      now = TimeHelpers.now()
      expired_at = DateTime.add(now, -60, :second)

      reservation =
        Repo.get_by!(StorageReservation,
          project_snapshot_id_snapshot: snapshot.id,
          status: "active"
        )

      reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: expired_at
      )
      |> Repo.update!()

      assert Versioning.list_expired_project_snapshot_build_candidates(now) == []

      snapshot.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(state: "discarded")
      |> Repo.update!()

      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)

      assert {:ok, intent} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate, now)

      assert intent.reason == "expired_build"
      assert intent.authority_kind == "system"
      refute Repo.get(ProjectSnapshot, snapshot.id)
      assert Repo.get!(StorageReservation, reservation.id).status == "released"
    end

    test "revalidates owning job state under lock" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      now = TimeHelpers.now()

      reservation =
        Repo.get_by!(StorageReservation,
          project_snapshot_id_snapshot: snapshot.id,
          status: "active"
        )

      reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

      job = Repo.get!(Oban.Job, snapshot.build_job_id)
      discarded_job = job |> Ecto.Changeset.change(state: "discarded") |> Repo.update!()
      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)
      discarded_job |> Ecto.Changeset.change(state: "available") |> Repo.update!()

      assert {:error, :expired_build_candidate_changed} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate, now)

      assert Repo.get!(ProjectSnapshot, snapshot.id).lifecycle_state == "pending"
      assert Repo.get!(StorageReservation, reservation.id).status == "active"
    end
  end

  describe "parent hard deletion" do
    test "project deletion leaves exact snapshot cleanup intent after the cascade" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, deleted} = Projects.delete_project(project, user.id)

      assert {:ok, _project} = Projects.permanently_delete_project(deleted)

      refute Repo.get(Projects.Project, project.id)
      refute Repo.get(ProjectSnapshot, ready.id)

      intent = Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: ready.id)
      assert intent.reason == "project_hard_delete"
      assert intent.authority_kind == "system"
      assert ready.manifest_storage_key in intent.storage_keys
    end

    test "workspace deletion records cleanup before deleting every project" do
      user = user_fixture()
      project = project_fixture(user)
      workspace = Repo.preload(project, :workspace).workspace
      ready = create_ready_snapshot(user, project)

      assert {:ok, _workspace} = Workspaces.delete_workspace(workspace)

      refute Repo.get(Workspaces.Workspace, workspace.id)
      intent = Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: ready.id)
      assert intent.reason == "workspace_hard_delete"
      assert intent.workspace_id_snapshot == workspace.id
    end

    test "project deletion fails closed while a build job can still write" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      assert Repo.get!(Oban.Job, snapshot.build_job_id).state == "available"
      assert {:ok, deleted} = Projects.delete_project(project, user.id)

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Projects.permanently_delete_project(deleted)

      assert Repo.get!(Projects.Project, project.id)
      assert Repo.get!(ProjectSnapshot, snapshot.id)
      assert Repo.get_by!(StorageReservation, project_snapshot_id_snapshot: snapshot.id).status == "active"
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "project deletion fails closed before loading an oversized snapshot inventory" do
      set_hard_delete_snapshot_limit(1)
      user = user_fixture()
      project = project_fixture(user)
      first = create_ready_snapshot(user, project)
      second = create_ready_snapshot(user, project)
      assert {:ok, deleted} = Projects.delete_project(project, user.id)

      assert {:error, :snapshot_parent_cleanup_limit_exceeded} =
               Projects.permanently_delete_project(deleted)

      assert Repo.get!(Projects.Project, project.id)
      assert Repo.get!(ProjectSnapshot, first.id)
      assert Repo.get!(ProjectSnapshot, second.id)
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "workspace deletion fails closed before partially recording oversized cleanup" do
      set_hard_delete_snapshot_limit(1)
      user = user_fixture()
      first_project = project_fixture(user)
      workspace = Repo.preload(first_project, :workspace).workspace
      second_project = project_fixture(user, %{workspace: workspace})
      first = create_ready_snapshot(user, first_project)
      second = create_ready_snapshot(user, second_project)

      assert {:error, :snapshot_parent_cleanup_limit_exceeded} =
               Workspaces.delete_workspace(workspace)

      assert Repo.get!(Workspaces.Workspace, workspace.id)
      assert Repo.get!(ProjectSnapshot, first.id)
      assert Repo.get!(ProjectSnapshot, second.id)
      refute Repo.exists?(SnapshotCleanupIntent)
    end
  end

  defp create_ready_snapshot(user, project) do
    assert {:ok, requested} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job = Repo.get!(Oban.Job, requested.build_job_id)
    assert :ok = BuildProjectSnapshotWorker.perform(%{job | attempt: 1})
    Repo.get!(ProjectSnapshot, requested.id)
  end

  defp set_hard_delete_snapshot_limit(limit) do
    original = Application.fetch_env!(:storyarn, :snapshot_lifecycle)

    Application.put_env(
      :storyarn,
      :snapshot_lifecycle,
      Keyword.put(original, :hard_delete_snapshot_limit, limit)
    )

    on_exit(fn -> Application.put_env(:storyarn, :snapshot_lifecycle, original) end)
  end
end
