defmodule Storyarn.Versioning.ProjectSnapshotRestoreActorLockConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.ProjectSnapshotRestore
  alias Storyarn.Versioning.ProjectSnapshotRestoreExecutor
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @poll_interval 20

  defmodule ArchiveReader do
    @moduledoc false
    @project_object_key {__MODULE__, :project_object}

    def put_project_object(project_object), do: :persistent_term.put(@project_object_key, project_object)
    def clear, do: :persistent_term.erase(@project_object_key)

    def verify(_snapshot) do
      {:ok,
       %{
         manifest: %{"assets" => [], "objects" => [%{"kind" => "project"}]},
         project: :persistent_term.get(@project_object_key)
       }}
    end
  end

  defmodule EmptyMaterializer do
    @moduledoc false

    alias Storyarn.Versioning.ProjectSnapshotAssetMaterializer.Plan

    def prepare(project_id, restore_id, _manifest, _project, prefix, _keys, _opts) do
      {:ok,
       %Plan{
         project_id: project_id,
         restore_identity: to_string(restore_id),
         staging_prefix: prefix,
         assets: [],
         blobs: [],
         source_refs: %{},
         logical_bytes: 0,
         staging_bytes: 0
       }}
    end

    def stage_destination_objects(_plan, _tracker), do: :ok

    def adopt_locked(_plan, _project, _actor, _tracker) do
      {:ok, %{assets: [], logical_id_map: %{}, source_id_map: %{}}}
    end

    def verify_adopted_locked(_plan, _map), do: :ok
  end

  defmodule BarrierRecovery do
    @moduledoc false
    @barrier_key {__MODULE__, :barrier}

    def arm(parent, barrier), do: :persistent_term.put(@barrier_key, {parent, barrier})
    def clear, do: :persistent_term.erase(@barrier_key)

    def validate_materialization_snapshot(project), do: ProjectRecovery.validate_materialization_snapshot(project)

    def lock_materializable_localization_actors(project, opts) do
      result = ProjectRecovery.lock_materializable_localization_actors(project, opts)
      pause_after_prelock(result)
      result
    end

    def materialize_into_project(project, snapshot, actor, source_ids, opts),
      do: ProjectRecovery.materialize_into_project(project, snapshot, actor, source_ids, opts)

    defp pause_after_prelock(result) do
      case :persistent_term.get(@barrier_key, nil) do
        {parent, barrier} ->
          :persistent_term.erase(@barrier_key)
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :actors_prelocked, self(), backend_pid, result})

          receive do
            {^barrier, :continue} -> :ok
          after
            15_000 -> exit(:actor_prelock_barrier_timeout)
          end

        nil ->
          :ok
      end
    end
  end

  test "a requested project owner delete cannot invert Project and User locks" do
    context = setup_fixture(:requested_owner)
    on_exit(fn -> cleanup_fixture(context) end)

    barrier = make_ref()
    BarrierRecovery.arm(self(), barrier)
    deleter = user_deleter(context.owner.id, self(), barrier)

    assert_receive {^barrier, :user_locked, deleter_pid, deleter_backend_pid}, @timeout

    executor = restore_executor(context.restore, self())

    assert_receive {
                     ^barrier,
                     :actors_prelocked,
                     executor_pid,
                     executor_backend_pid,
                     {:error, {:project_materialization_localization_actors_busy, busy_actor_ids}}
                   },
                   @timeout

    assert busy_actor_ids == [context.owner.id]
    send(deleter_pid, {barrier, :delete})

    assert_eventually_blocked_by(deleter_backend_pid, executor_backend_pid)
    refute blocked_by?(executor_backend_pid, deleter_backend_pid)

    send(executor_pid, {barrier, :continue})

    assert {:retry, :project_materialization_localization_actors_busy} =
             Task.await(executor, @timeout)

    assert {:delete_error, error} = Task.await(deleter, @timeout)
    refute error =~ "40P01"
    refute error =~ "deadlock detected"

    restore = prepare_retry(context.restore.id, 2)

    assert {:ok, %ProjectSnapshotRestore{result: %{"semantic_digest" => semantic_digest}}} =
             restore |> restore_executor(self(), 2) |> Task.await(@timeout)

    assert is_binary(semantic_digest)

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.get(User, context.owner.id)
      assert Repo.get!(ProjectSnapshotRestore, context.restore.id).status == "completed"
      assert active_restored_text(context).translated_by_id == context.owner.id
    end)
  end

  test "a deleting project actor is skipped and restored localization is normalized to nil" do
    context = setup_fixture(:distinct_deleted_by)
    on_exit(fn -> cleanup_fixture(context) end)

    barrier = make_ref()
    BarrierRecovery.arm(self(), barrier)
    deleter = user_deleter(context.reviewer.id, self(), barrier)

    assert_receive {^barrier, :user_locked, deleter_pid, deleter_backend_pid}, @timeout

    executor = restore_executor(context.restore, self())

    assert_receive {
                     ^barrier,
                     :actors_prelocked,
                     executor_pid,
                     executor_backend_pid,
                     {:error, {:project_materialization_localization_actors_busy, busy_actor_ids}}
                   },
                   @timeout

    assert busy_actor_ids == [context.reviewer.id]
    send(deleter_pid, {barrier, :delete})

    assert_eventually_blocked_by(deleter_backend_pid, executor_backend_pid)
    refute blocked_by?(executor_backend_pid, deleter_backend_pid)

    send(executor_pid, {barrier, :continue})

    assert {:retry, :project_materialization_localization_actors_busy} =
             Task.await(executor, @timeout)

    assert {:ok, %User{id: reviewer_id}} = Task.await(deleter, @timeout)
    assert reviewer_id == context.reviewer.id

    restore = prepare_retry(context.restore.id, 2)

    assert {:ok, %ProjectSnapshotRestore{result: %{"semantic_digest" => semantic_digest}}} =
             restore |> restore_executor(self(), 2) |> Task.await(@timeout)

    assert is_binary(semantic_digest)

    Sandbox.unboxed_run(Repo, fn ->
      refute Repo.get(User, context.reviewer.id)
      assert Repo.get!(ProjectSnapshotRestore, context.restore.id).status == "completed"

      restored_text = active_restored_text(context)

      assert restored_text.translated_by_id == context.owner.id
      assert restored_text.reviewed_by_id == nil
    end)
  end

  defp setup_fixture(mode) do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture(%{email: "actor-lock-owner-#{Ecto.UUID.generate()}@example.com"})
      project = project_fixture(owner)
      _source_language = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _target_language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      reviewer = actor_for_mode(mode, project)
      flow = flow_fixture(project, %{name: "Actor lock dialogue"})
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
      text = Localization.get_text_by_source("flow_node", dialogue.id, "text", "es")

      actor_attrs =
        maybe_put_reviewer(%{translated_text: "Hola", status: "final", translated_by_id: owner.id}, mode, reviewer)

      assert {:ok, text} = Localization.update_text(text, actor_attrs)
      project = maybe_mark_deleted_by(project, mode, reviewer)
      project_object = active_project_object(project.id)

      snapshot =
        full_project_snapshot_fixture(project, %{
          asset_blob_size_bytes: 0
        })

      restore = request_and_claim_restore(owner, project, snapshot)

      ArchiveReader.put_project_object(project_object)

      %{
        owner: owner,
        reviewer: reviewer,
        project: project,
        workspace: Repo.get!(Workspace, project.workspace_id),
        snapshot: snapshot,
        restore: restore,
        text: text
      }
    end)
  end

  defp actor_for_mode(:requested_owner, _project), do: nil

  defp actor_for_mode(:distinct_deleted_by, _project) do
    Repo.insert!(%User{email: "actor-lock-reviewer-#{Ecto.UUID.generate()}@example.com"})
  end

  defp maybe_put_reviewer(attrs, :requested_owner, _reviewer), do: attrs
  defp maybe_put_reviewer(attrs, :distinct_deleted_by, reviewer), do: Map.put(attrs, :reviewed_by_id, reviewer.id)

  defp maybe_mark_deleted_by(project, :requested_owner, _reviewer), do: project

  defp maybe_mark_deleted_by(project, :distinct_deleted_by, reviewer) do
    {1, nil} =
      Repo.update_all(from(candidate in Project, where: candidate.id == ^project.id), set: [deleted_by_id: reviewer.id])

    Repo.reload!(project)
  end

  defp active_project_object(project_id) do
    {:ok, snapshot} =
      Repo.repeatable_read(fn ->
        ProjectSnapshotBuilder.build_snapshot_in_transaction(project_id,
          localization_scope: :active
        )
      end)

    normalized = snapshot |> Jason.encode!() |> Jason.decode!()
    {:ok, portable} = SnapshotObjectFormat.portable_project(normalized)

    Map.put(portable, "asset_catalog_refs", %{})
  end

  defp request_and_claim_restore(owner, project, snapshot) do
    assert {:ok, requested} =
             Versioning.request_project_snapshot_restore(
               user_scope_fixture(owner),
               project,
               snapshot,
               %{idempotency_key: Ecto.UUID.generate()}
             )

    job =
      requested.oban_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert {:ok, {:claimed, restore}} =
             Versioning.claim_project_snapshot_restore(requested.id, 1,
               job_id: job.id,
               attempt: 1
             )

    restore
  end

  defp user_deleter(user_id, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Repo.transaction(fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          user = Repo.one!(from candidate in User, where: candidate.id == ^user_id, lock: "FOR UPDATE")
          send(parent, {barrier, :user_locked, self(), backend_pid})

          receive do
            {^barrier, :delete} -> Repo.delete!(user)
          after
            @timeout -> Repo.rollback(:delete_barrier_timeout)
          end
        end)
      rescue
        error -> {:delete_error, Exception.message(error)}
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp restore_executor(restore, _parent, attempt \\ 1) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        job = Repo.get!(Oban.Job, restore.oban_job_id)

        Versioning.perform_project_snapshot_restore(
          restore.id,
          job.args["generation"],
          job_id: job.id,
          attempt: attempt,
          max_attempts: 3,
          executor: &execute_claimed_restore/2
        )
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp execute_claimed_restore(restore, _opts) do
    ProjectSnapshotRestoreExecutor.execute(restore,
      archive_reader: ArchiveReader,
      asset_materializer: EmptyMaterializer,
      project_recovery: BarrierRecovery
    )
  end

  defp prepare_retry(restore_id, attempt) do
    Sandbox.unboxed_run(Repo, fn ->
      restore = Repo.get!(ProjectSnapshotRestore, restore_id)

      restore.oban_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: attempt,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

      restore
    end)
  end

  defp assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, attempts \\ div(@timeout, @poll_interval))

  defp assert_eventually_blocked_by(_waiter_backend_pid, _holder_backend_pid, 0) do
    flunk("expected database wait edge never appeared")
  end

  defp assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, attempts) do
    if blocked_by?(waiter_backend_pid, holder_backend_pid) do
      :ok
    else
      Process.sleep(@poll_interval)
      assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, attempts - 1)
    end
  end

  defp blocked_by?(waiter_backend_pid, holder_backend_pid) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("SELECT $2 = ANY(pg_blocking_pids($1))", [waiter_backend_pid, holder_backend_pid]).rows == [[true]]
    end)
  end

  defp active_restored_text(context) do
    Repo.one!(
      from text in LocalizedText,
        where:
          text.project_id == ^context.project.id and is_nil(text.archived_at) and
            text.source_type == "flow_node" and text.source_id != ^context.text.source_id and
            text.source_field == "text"
    )
  end

  defp cleanup_fixture(context) do
    BarrierRecovery.clear()
    ArchiveReader.clear()

    Sandbox.unboxed_run(Repo, fn ->
      job_ids =
        Repo.all(
          from restore in ProjectSnapshotRestore,
            where: restore.project_id == ^context.project.id,
            select: restore.oban_job_id
        )

      Repo.delete_all(from project in Project, where: project.id == ^context.project.id)
      Repo.delete_all(from job in Oban.Job, where: job.id in ^job_ids)
      Repo.delete_all(from workspace in Workspace, where: workspace.id == ^context.workspace.id)

      user_ids = Enum.reject([context.owner.id, context.reviewer && context.reviewer.id], &is_nil/1)
      Repo.delete_all(from user in User, where: user.id in ^user_ids)
    end)
  end
end
