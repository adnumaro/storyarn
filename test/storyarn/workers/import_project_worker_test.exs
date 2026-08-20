defmodule Storyarn.Workers.ImportProjectWorkerTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Imports
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Repo
  alias Storyarn.Workers.ImportProjectWorker

  test "snapshot snoozes preserve the three-attempt import failure budget" do
    assert Keyword.fetch!(ImportProjectWorker.__opts__(), :queue) == :imports
    assert Keyword.fetch!(ImportProjectWorker.__opts__(), :max_attempts) == 3

    for logical_attempt <- 1..3 do
      errors = List.duplicate(%{}, logical_attempt - 1)
      snoozed = %Oban.Job{attempt: 40 + logical_attempt, max_attempts: 43, errors: errors}
      logical = %Oban.Job{attempt: logical_attempt, max_attempts: 3}

      assert seeded_backoff(snoozed) == seeded_oban_backoff(logical)
      assert ImportProjectWorker.canonical_attempt(snoozed) == logical_attempt
    end
  end

  test "many snapshot waits cannot produce a multi-day import backoff" do
    snoozed = %Oban.Job{attempt: 721, max_attempts: 723, errors: []}

    assert ImportProjectWorker.canonical_attempt(snoozed) == 1
    assert seeded_backoff(snoozed) in 17..18
  end

  test "perform passes a real pending checkpoint through as an Oban snooze" do
    user = user_fixture()
    project = project_fixture(user)
    scope = Scope.for_user(user)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(scope, project, "worker-replacement.zip", replaceable_yarn_archive())

    assert {:ok, selected} = Imports.update_import_mode(scope, ready.id, "replace_project")

    assert {:ok, queued} =
             Imports.enqueue_import(scope, selected.id, :rename,
               import_mode: "replace_project",
               replace_acknowledged: true
             )

    job = %Oban.Job{
      args: %{"attempt_id" => queued.id},
      attempt: 1,
      max_attempts: 3,
      errors: []
    }

    assert {:snooze, 5} = ImportProjectWorker.perform(job)

    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    assert waiting.status == "queued"
    assert waiting.stage == "awaiting_snapshot"
    assert is_integer(waiting.pre_import_snapshot_id)
    assert %DateTime{} = waiting.snapshot_reference_bound_at
  end

  defp seeded_backoff(job) do
    :rand.seed(:exsss, {201, 202, 203})
    ImportProjectWorker.backoff(job)
  end

  defp seeded_oban_backoff(job) do
    :rand.seed(:exsss, {201, 202, 203})
    Oban.Worker.backoff(job)
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
      {~c"main.yarn", "title: Start\n---\nA new beginning.\n===\n"}
    ]

    {:ok, {_name, binary}} = :zip.create(~c"worker-replacement.zip", entries, [:memory])
    binary
  end
end
