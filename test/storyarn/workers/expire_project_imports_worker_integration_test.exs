defmodule Storyarn.Workers.ExpireProjectImportsWorkerIntegrationTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Imports
  alias Storyarn.Projects.Imports.PlanCleanupRequest
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Repo
  alias Storyarn.Workers.ExpireProjectImportsWorker

  test "reports and drains an attempt backlog larger than one bounded batch" do
    user = user_fixture()
    project = project_fixture(user)
    now = TimeHelpers.now()
    stale_at = DateTime.add(now, -600, :second)
    expires_at = DateTime.add(now, -60, :second)
    storage_keys = Enum.map(1..101, &storage_key/1)

    insert_cleanup_requests(storage_keys, project.id, now, "retained", nil)

    cleanup_ids =
      PlanCleanupRequest
      |> where([request], request.plan_storage_key in ^storage_keys)
      |> select([request], {request.plan_storage_key, request.id})
      |> Repo.all()
      |> Map.new()

    attempt_rows =
      storage_keys
      |> Enum.with_index(1)
      |> Enum.map(fn {key, index} ->
        %{
          project_id: project.id,
          user_id: user.id,
          plan_cleanup_request_id: Map.fetch!(cleanup_ids, key),
          status: "ready",
          stage: "parsed",
          format: "yarn",
          source_kind: "file",
          parser_version: "2",
          conflict_strategy: "rename",
          idempotency_key: String.pad_leading(Integer.to_string(index), 64, "0"),
          plan_storage_key: key,
          counts: %{},
          warning_codes: [],
          error_report: %{},
          expires_at: expires_at,
          inserted_at: stale_at,
          updated_at: stale_at
        }
      end)

    assert {101, nil} = Repo.insert_all(ProjectImportAttempt, attempt_rows)

    opts = [stale_batch_size: 100, plan_delete: fn _storage_key -> :ok end]

    assert {:ok, %{expired_count: 100, failure_count: 0, more?: true}} =
             Imports.expire_stale_imports_batch(opts)

    assert Repo.aggregate(
             from(attempt in ProjectImportAttempt, where: attempt.status == "ready"),
             :count
           ) == 1

    assert {:ok, %{expired_count: 1, failure_count: 0, more?: false}} =
             Imports.expire_stale_imports_batch(opts)

    assert Repo.aggregate(
             from(attempt in ProjectImportAttempt, where: attempt.status == "expired"),
             :count
           ) == 101

    assert Repo.aggregate(
             from(request in PlanCleanupRequest, where: request.state == "completed"),
             :count
           ) == 101
  end

  test "reports and drains a cleanup backlog larger than one bounded batch" do
    now = TimeHelpers.now()
    due_at = DateTime.add(now, -60, :second)
    storage_keys = Enum.map(1..101, &storage_key/1)

    insert_cleanup_requests(storage_keys, nil, now, "pending", due_at)

    assert :ok = perform_job(ExpireProjectImportsWorker, %{})
    assert_enqueued(worker: ExpireProjectImportsWorker, args: %{})

    assert Repo.aggregate(
             from(request in PlanCleanupRequest, where: request.state == "pending"),
             :count
           ) == 1

    assert :ok = perform_job(ExpireProjectImportsWorker, %{})

    assert Repo.aggregate(
             from(request in PlanCleanupRequest, where: request.state == "completed"),
             :count
           ) == 101
  end

  defp insert_cleanup_requests(storage_keys, project_id, now, state, cleanup_after) do
    rows =
      Enum.map(storage_keys, fn key ->
        %{
          project_id: project_id,
          plan_storage_key: key,
          format: "yarn",
          parser_version: "2",
          state: state,
          cleanup_after: cleanup_after,
          attempt_count: 0,
          generation: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    row_count = length(rows)
    assert {^row_count, nil} = Repo.insert_all(PlanCleanupRequest, rows)
  end

  defp storage_key(index) do
    suffix =
      index
      |> Integer.to_string()
      |> String.pad_leading(12, "0")

    "imports/plans/00000000-0000-0000-0000-#{suffix}.plan.enc"
  end
end
