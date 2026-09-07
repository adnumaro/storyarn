defmodule Storyarn.Ideation.RecoveryLimitsTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  @moduletag timeout: 120_000

  setup do
    ideation_fixture()
  end

  test "capture returns the size error and the background build records it without retries", ctx do
    # Large persisted fixture exercises the real byte bound, without changing
    # production limits or allocating 100,000 separate domain records.
    set_context(ctx, "x", 49)

    assert {:error, :ideation_recovery_too_large} =
             Repo.transact(fn ->
               {:ok,
                ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id,
                  localization_scope: :active
                )}
             end)

    assert {:ok, requested} =
             Projects.request_full_project_snapshot(ctx.owner, ctx.project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job = Repo.get!(Oban.Job, requested.build_job_id)

    job =
      job
      |> Ecto.Changeset.change(state: "executing", attempt: 1, attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}})
      |> Repo.update!()

    assert {:discard, :ideation_recovery_too_large} = BuildProjectSnapshotWorker.perform(job)
    failed = Repo.get!(ProjectSnapshot, requested.id)
    assert failed.lifecycle_state == "failed"
    assert failed.failure_code == "ideation_recovery_too_large"
    assert failed.failure_message == "The brainstorming recovery history exceeds the snapshot size limit."
  end

  test "restore rolls back if retaining a distinct generation would exceed capture limits", ctx do
    set_context(ctx, "a", 24)
    {:ok, capsule} = capture(ctx)
    set_context(ctx, "b", 24)

    assert {:error, :ideation_recovery_too_large} =
             Repo.transact(fn ->
               lock(ctx)
               Ideation.restore_recovery(ctx.project.id, capsule)
             end)

    assert Repo.aggregate(from(s in Session, where: s.project_id == ^ctx.project.id), :count) == 1
    assert Repo.one(from s in Session, where: s.id == ^ctx.session.id, select: is_nil(s.deleted_at))
    assert Repo.one(from s in Session, where: s.id == ^ctx.session.id, select: fragment("left(?, 1)", s.context)) == "b"
    assert {:ok, _} = capture(ctx)
  end

  test "invalid capture fails the background build with its own message on the first attempt", ctx do
    idea_fixture(ctx, %{visibility: :shared})
    # A malformed stored selection must still be rejected after allowing creation.
    Repo.update_all(from(r in Reveal, where: r.session_id == ^ctx.session.id),
      set: [selection: %{"mode" => "unsupported"}]
    )

    assert {:error, :ideation_recovery_capture_failed} = capture(ctx)

    assert {:ok, requested} =
             Projects.request_full_project_snapshot(ctx.owner, ctx.project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job = Repo.get!(Oban.Job, requested.build_job_id)

    job =
      job
      |> Ecto.Changeset.change(state: "executing", attempt: 1, attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}})
      |> Repo.update!()

    assert {:discard, :ideation_recovery_capture_failed} = BuildProjectSnapshotWorker.perform(job)
    failed = Repo.get!(ProjectSnapshot, requested.id)
    assert failed.lifecycle_state == "failed"
    assert failed.failure_code == "ideation_recovery_capture_failed"
    assert failed.failure_message == "The brainstorming data could not be captured for this snapshot."
  end

  defp capture(ctx) do
    Repo.transact(fn ->
      lock(ctx)
      Ideation.capture_recovery(ctx.project.id)
    end)
  end

  defp lock(ctx), do: Repo.one!(from p in Project, where: p.id == ^ctx.project.id, lock: "FOR UPDATE")

  defp set_context(ctx, character, megabytes) do
    Repo.update_all(from(s in Session, where: s.id == ^ctx.session.id),
      set: [context: String.duplicate(character, megabytes * 1024 * 1024)]
    )
  end
end
