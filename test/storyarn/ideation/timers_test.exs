defmodule Storyarn.Ideation.TimersTest do
  # This suite asserts the absence of global timer wakeups after rollback.
  # Run outside concurrent timer writers that legitimately publish that event.
  use Storyarn.DataCase, async: false

  import Ecto.Changeset
  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Project

  setup do
    ideation_fixture()
  end

  test "an optional timer starts without rounds or changes to privacy and expires as a notice", ctx do
    assert {:ok, nil} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    timer = start(ctx)
    assert timer.status == :running
    assert timer.version == 1
    assert timer.duration_seconds == 120
    assert timer.remaining_seconds == 120
    assert timer.actor_id == ctx.facilitator.user.id
    assert timer.configuration_version == 1
    assert timer.recovery_identity
    refute timer.reveal_on_expiry
    refute timer.close_contributions_on_expiry
    assert current(ctx).configuration == ctx.session.configuration
    assert {:ok, []} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert {:ok, %{outcome: :not_due}} = Ideation.expire_timer(timer.id, timer.version)

    assert {:error, :timer_already_running} =
             Ideation.start_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, %{seconds: 60})

    due(timer)
    assert {:ok, %{outcome: :completed, timer: elapsed}} = Ideation.expire_timer(timer.id, timer.version)
    assert elapsed.status == :elapsed
    assert elapsed.version == 2
    assert elapsed.deadline_at == nil
    assert elapsed.remaining_seconds == 0
    assert elapsed.expiry_outcome == :completed
    assert elapsed.completed_at
    assert current(ctx).contributions_open
    assert current(ctx).configuration == ctx.session.configuration
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, timer.version)
    assert current(ctx).revision == 3

    assert {:ok, [elapsed_revision, started_revision, _]} =
             Ideation.list_session_revisions(ctx.viewer, ctx.project.id, ctx.session.id)

    assert elapsed_revision.action == :timer_elapsed
    assert elapsed_revision.snapshot["timer"]["expiry_outcome"] == "completed"
    assert started_revision.action == :timer_started
  end

  test "pause, resume, extend and cancel fence old deadlines and preserve a single timer", ctx do
    timer = start(ctx)
    timer |> change(deadline_at: DateTime.shift(now(), second: 8)) |> Repo.update!()
    assert {:ok, _} = Ideation.pause_timer(ctx.facilitator, ctx.project.id, ctx.session.id, 2, timer.version)
    paused = timer(ctx)
    assert paused.status == :paused
    assert paused.remaining_seconds in 1..8
    assert paused.deadline_at == nil
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, timer.version)
    assert {:ok, _} = Ideation.resume_timer(ctx.owner, ctx.project.id, ctx.session.id, 3, paused.version)
    resumed = timer(ctx)
    assert resumed.actor_id == ctx.owner.user.id
    assert resumed.status == :running
    assert resumed.remaining_seconds == paused.remaining_seconds
    assert {:ok, _} = Ideation.extend_timer(ctx.owner, ctx.project.id, ctx.session.id, 4, resumed.version, 30)
    extended = timer(ctx)
    assert extended.duration_seconds == 150
    assert extended.remaining_seconds in 30..38
    assert DateTime.after?(extended.deadline_at, resumed.deadline_at)
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, resumed.version)
    assert {:ok, _} = Ideation.cancel_timer(ctx.owner, ctx.project.id, ctx.session.id, 5, extended.version)
    cancelled = timer(ctx)
    assert cancelled.status == :cancelled
    assert cancelled.deadline_at == nil
    assert cancelled.remaining_seconds == 0
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, extended.version)
    assert {:ok, _} = Ideation.cancel_timer(ctx.owner, ctx.project.id, ctx.session.id, 6, cancelled.version)
    assert current(ctx).revision == 6
    replacement = start(ctx, %{seconds: 30})
    assert replacement.id == timer.id
    assert replacement.version == cancelled.version + 1
    assert replacement.started_at
    assert replacement.completed_at == nil
    assert Repo.aggregate(Timer, :count) == 1
  end

  @tag :timer_clock_regression
  test "pausing after a backward clock adjustment cannot exceed the programmed duration", ctx do
    timer = start(ctx, %{seconds: 60})

    # Persist the same deadline-to-now gap a clock moving back one minute creates.
    timer |> change(deadline_at: DateTime.shift(now(), minute: 2)) |> Repo.update!()

    assert {:ok, _} = Ideation.pause_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, timer.version)
    paused = timer(ctx)
    assert paused.status == :paused
    assert paused.duration_seconds == 60
    assert paused.remaining_seconds == 60
    assert paused.deadline_at == nil
  end

  @tag :timer_clock_regression
  test "extending after a backward clock adjustment preserves the timer duration bound", ctx do
    timer = start(ctx, %{seconds: 60})
    timer |> change(deadline_at: DateTime.shift(now(), minute: 2)) |> Repo.update!()

    assert {:ok, _} = Ideation.extend_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, timer.version, 30)
    extended = timer(ctx)
    assert extended.status == :running
    assert extended.duration_seconds == 90
    assert extended.remaining_seconds == 90
    assert DateTime.diff(extended.deadline_at, now(), :second) in 1..90
    assert extended.version == timer.version + 1
  end

  @tag :timer_clock_regression
  test "cancellation after a backward clock adjustment remains recoverable", ctx do
    assert_terminal_clock_recovery(ctx, :cancel)
  end

  @tag :timer_clock_regression
  test "archiving after a backward clock adjustment remains recoverable", ctx do
    assert_terminal_clock_recovery(ctx, :archive)
  end

  @tag :timer_clock_regression
  test "expiry after rescheduling across a backward clock adjustment remains recoverable", ctx do
    assert_terminal_clock_recovery(ctx, :expire)
  end

  test "timer controls authorize managers with current session and timer versions", ctx do
    for actor <- [ctx.author, ctx.peer, ctx.viewer] do
      assert {:error, :unauthorized} = Ideation.start_timer(actor, ctx.project.id, ctx.session.id, 1, %{seconds: 60})
      assert {:error, :unauthorized} = Ideation.set_contributions_open(actor, ctx.project.id, ctx.session.id, 1, false)
    end

    timer = start(ctx)

    for actor <- [ctx.author, ctx.peer, ctx.viewer] do
      assert {:error, :unauthorized} = Ideation.pause_timer(actor, ctx.project.id, ctx.session.id, 2, 1)
      assert {:error, :unauthorized} = Ideation.resume_timer(actor, ctx.project.id, ctx.session.id, 2, 1)
      assert {:error, :unauthorized} = Ideation.extend_timer(actor, ctx.project.id, ctx.session.id, 2, 1, 30)
      assert {:error, :unauthorized} = Ideation.cancel_timer(actor, ctx.project.id, ctx.session.id, 2, 1)
    end

    assert {:error, :stale_revision} = Ideation.pause_timer(ctx.owner, ctx.project.id, ctx.session.id, 1, 1)
    assert {:error, :stale_timer} = Ideation.pause_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, 99)
    assert {:error, :invalid_timer_version} = Ideation.pause_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, "1")
    assert {:error, :timer_not_paused} = Ideation.resume_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, 1)
    assert {:ok, other} = Ideation.create_session(ctx.owner, ctx.project.id, %{title: "Other"})
    assert {:error, :timer_not_found} = Ideation.cancel_timer(ctx.owner, ctx.project.id, other.id, 1, timer.version)
    assert {:ok, nil} = Ideation.get_timer(ctx.viewer, ctx.project.id, other.id)
    assert {:error, :not_found} = Ideation.get_timer(ctx.viewer, ctx.project.id, -1)

    membership = Projects.get_membership(ctx.project.id, ctx.facilitator.user.id)
    assert {:ok, _} = Projects.update_member_role(ctx.owner, ctx.project.id, membership.id, "viewer")
    assert {:error, :unauthorized} = Ideation.cancel_timer(ctx.facilitator, ctx.project.id, ctx.session.id, 2, 1)
    due(timer)
    assert {:ok, %{outcome: :skipped_authorization}} = Ideation.expire_timer(timer.id, timer.version)
  end

  test "closing contributions only blocks new creations and replay remains valid", ctx do
    attrs = idea_attrs()
    assert {:ok, idea} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    deleted = idea_fixture(ctx)
    assert {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, deleted.id, deleted.revision)
    assert {:ok, _} = Ideation.set_contributions_open(ctx.facilitator, ctx.project.id, ctx.session.id, 1, false)
    assert current(ctx).configuration_version == 1
    assert {:ok, ^idea} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)

    assert {:error, :contributions_closed} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())

    assert {:error, :contributions_closed} =
             Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, %{
               request_key: Ecto.UUID.generate(),
               body: "New"
             })

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               idea.revision,
               edit_attrs(%{body: "Edited"})
             )

    assert {:ok, _} =
             Ideation.restore_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               deleted.id,
               deleted.revision,
               deleted.deleted_at
             )

    assert {:ok, _} = Ideation.set_contributions_open(ctx.owner, ctx.project.id, ctx.session.id, 2, true)
    assert idea_fixture(ctx)
  end

  test "expiry atomically closes contributions and reveals exactly the manual policy", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    private(ctx)
    configuration_version = current(ctx).configuration_version

    notes =
      for state <- [:active, :parked, :discarded], into: %{} do
        attrs = %{request_key: Ecto.UUID.generate(), body: Atom.to_string(state), state: state}
        assert {:ok, note} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
        {state, note}
      end

    legacy = idea_fixture(ctx, %{configuration_version: configuration_version, body: "Legacy private"})

    assert {:ok, orphan} =
             Ideation.create_canvas_idea(ctx.peer, ctx.project.id, ctx.session.id, %{
               request_key: Ecto.UUID.generate(),
               body: "Orphan"
             })

    Idea |> Repo.get!(orphan.id) |> change(author_id: nil) |> Repo.update!()
    timer = start(ctx, %{reveal_on_expiry: true, close_contributions_on_expiry: true})
    due(timer)

    assert {:ok, %{outcome: :completed}} = Ideation.expire_timer(timer.id, timer.version)
    refute current(ctx).configuration.private_mode
    refute current(ctx).contributions_open

    for note <- [notes.active, notes.parked] do
      assert {:ok, visible} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, note.id)
      assert visible.visibility == :shared
    end

    for note <- [notes.discarded, legacy, orphan] do
      assert {:error, :not_found} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, note.id)
    end

    assert Repo.aggregate(Reveal, :count) == 1
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, timer.version)
    assert Repo.aggregate(Reveal, :count) == 1
  end

  test "changed configuration, manager replacement and missing actors cannot apply scheduled effects", ctx do
    private(ctx)
    timer = start(ctx, %{reveal_on_expiry: true, close_contributions_on_expiry: true})
    session = current(ctx)

    assert {:ok, _} =
             Ideation.update_session(ctx.owner, ctx.project.id, ctx.session.id, session.revision, %{
               configuration: %{rounds_enabled: true}
             })

    due(timer)
    assert {:ok, %{outcome: :skipped_configuration}} = Ideation.expire_timer(timer.id, timer.version)
    assert current(ctx).configuration.private_mode
    assert current(ctx).contributions_open
    assert Repo.aggregate(Reveal, :count) == 0

    timer = start(ctx, %{reveal_on_expiry: true, close_contributions_on_expiry: true})
    session = current(ctx)

    assert {:ok, _} =
             Ideation.assign_session_responsibilities(ctx.owner, ctx.project.id, ctx.session.id, session.revision, %{
               facilitator_id: ctx.peer.user.id,
               decision_owner_id: ctx.owner.user.id
             })

    due(timer)
    assert {:ok, %{outcome: :skipped_authorization}} = Ideation.expire_timer(timer.id, timer.version)
    assert current(ctx).configuration.private_mode
    assert current(ctx).contributions_open

    timer = start(ctx, %{reveal_on_expiry: true}, ctx.owner)
    timer |> due() |> change(actor_id: nil) |> Repo.update!()
    assert {:ok, %{outcome: :skipped_authorization}} = Ideation.expire_timer(timer.id, timer.version)
    assert current(ctx).configuration.private_mode
  end

  test "resuming explicitly renews scheduler authority and configuration, and never reveals without private mode", ctx do
    private(ctx)
    timer = start(ctx, %{reveal_on_expiry: true})

    assert {:ok, _} =
             Ideation.pause_timer(ctx.owner, ctx.project.id, ctx.session.id, current(ctx).revision, timer.version)

    paused = timer(ctx)
    assert {:ok, _} = Ideation.set_private_mode(ctx.owner, ctx.project.id, ctx.session.id, current(ctx).revision, false)

    assert {:error, :timer_reveal_requires_private} =
             Ideation.resume_timer(ctx.owner, ctx.project.id, ctx.session.id, current(ctx).revision, paused.version)

    private(ctx)

    assert {:ok, _} =
             Ideation.resume_timer(ctx.owner, ctx.project.id, ctx.session.id, current(ctx).revision, paused.version)

    resumed = timer(ctx)
    assert resumed.actor_id == ctx.owner.user.id
    assert resumed.configuration_version == current(ctx).configuration_version
    due(resumed)
    assert {:ok, %{outcome: :completed}} = Ideation.expire_timer(resumed.id, resumed.version)
  end

  test "archiving cancels timers and reopening never revives deadlines", ctx do
    private(ctx)
    timer = start(ctx, %{reveal_on_expiry: true, close_contributions_on_expiry: true})
    assert {:ok, archived} = Ideation.archive_session(ctx.owner, ctx.project.id, ctx.session.id, current(ctx).revision)
    cancelled = timer(ctx)
    assert cancelled.status == :cancelled
    assert cancelled.version == timer.version + 1
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, timer.version)

    assert {:error, :session_archived} =
             Ideation.start_timer(ctx.owner, ctx.project.id, ctx.session.id, archived.revision, %{seconds: 60})

    assert {:error, :session_archived} =
             Ideation.set_contributions_open(ctx.owner, ctx.project.id, ctx.session.id, archived.revision, false)

    assert {:ok, _} = Ideation.reopen_session(ctx.owner, ctx.project.id, ctx.session.id, archived.revision)
    assert timer(ctx).status == :cancelled
    assert current(ctx).contributions_open
  end

  test "boundaries reject malformed options, overlong timers and elapsed pause or extension", ctx do
    for seconds <- [nil, "60", 1.5, 0, 14, 86_401] do
      assert {:error, :invalid_timer_duration} =
               Ideation.start_timer(ctx.owner, ctx.project.id, ctx.session.id, 1, %{seconds: seconds})
    end

    for value <- [nil, "true", 1, %{}] do
      assert {:error, :invalid_timer_options} =
               Ideation.start_timer(ctx.owner, ctx.project.id, ctx.session.id, 1, %{seconds: 15, reveal_on_expiry: value})
    end

    assert {:error, :timer_reveal_requires_private} =
             Ideation.start_timer(ctx.owner, ctx.project.id, ctx.session.id, 1, %{seconds: 15, reveal_on_expiry: true})

    timer = start(ctx, %{seconds: 86_400, actor_id: ctx.peer.user.id, status: :elapsed, version: 99})
    assert timer.version == 1
    assert timer.actor_id == ctx.facilitator.user.id
    assert timer.status == :running
    assert {:error, :invalid_timer_duration} = Ideation.extend_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, 1, 1)

    assert {:error, :invalid_timer_duration} =
             Ideation.extend_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, 1, "30")

    due(timer)
    assert {:error, :timer_expired} = Ideation.pause_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, 1)
    assert {:error, :timer_expired} = Ideation.extend_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, 1, 1)
    assert {:ok, %{outcome: :not_found}} = Ideation.expire_timer(9_000_000_000, 1)
  end

  test "a surrounding rollback cannot leave publication or completion behind", ctx do
    private(ctx)

    assert {:ok, idea} =
             Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, %{
               request_key: Ecto.UUID.generate(),
               body: "Private"
             })

    timer = start(ctx, %{reveal_on_expiry: true, close_contributions_on_expiry: true})
    due(timer)
    Phoenix.PubSub.subscribe(Storyarn.PubSub, "ideation:timers")

    assert {:error, :rollback} =
             Repo.transact(fn ->
               assert {:ok, %{outcome: :completed}} = Ideation.expire_timer(timer.id, timer.version)
               {:error, :rollback}
             end)

    refute_receive :ideation_timers_changed
    assert timer(ctx).status == :running
    assert current(ctx).configuration.private_mode
    assert current(ctx).contributions_open
    assert {:error, :not_found} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, idea.id)
    assert Repo.aggregate(Reveal, :count) == 0
  end

  defp assert_terminal_clock_recovery(ctx, action) do
    timer = start(ctx, %{seconds: 60})
    original_start = DateTime.shift(now(), minute: 1)

    timer
    |> change(started_at: original_start, deadline_at: DateTime.shift(now(), minute: 2))
    |> Repo.update!()

    case action do
      :cancel ->
        assert {:ok, _} = Ideation.cancel_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, timer.version)

      :archive ->
        assert {:ok, _} = Ideation.archive_session(ctx.owner, ctx.project.id, ctx.session.id, 2)

      :expire ->
        # A timer resumed or extended after the clock moved back can become due
        # before its original start timestamp in wall-clock coordinates.
        due(timer)
        assert {:ok, %{outcome: :completed}} = Ideation.expire_timer(timer.id, timer.version)
    end

    assert {:ok, capsule} =
             Repo.transact(fn ->
               Repo.one!(from p in Project, where: p.id == ^ctx.project.id, lock: "FOR UPDATE")
               Ideation.capture_recovery(ctx.project.id)
             end)

    assert {:ok, _} = Capsule.open(capsule)
    completed = timer(ctx)
    refute DateTime.before?(completed.completed_at, original_start)
    assert completed.remaining_seconds == 0
  end

  defp current(ctx) do
    {:ok, session} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)
    session
  end

  defp timer(ctx) do
    {:ok, timer} = Ideation.get_timer(ctx.owner, ctx.project.id, ctx.session.id)
    timer
  end

  defp start(ctx, attrs \\ %{}, actor \\ nil) do
    attrs = Map.merge(%{seconds: 120}, attrs)

    assert {:ok, _} =
             Ideation.start_timer(actor || ctx.facilitator, ctx.project.id, ctx.session.id, current(ctx).revision, attrs)

    timer(ctx)
  end

  defp private(ctx) do
    assert {:ok, _} = Ideation.set_private_mode(ctx.owner, ctx.project.id, ctx.session.id, current(ctx).revision, true)
  end

  defp due(timer), do: timer |> change(deadline_at: DateTime.shift(now(), second: -1)) |> Repo.update!()
  defp now, do: %{TimeHelpers.now() | microsecond: {0, 6}}
end
