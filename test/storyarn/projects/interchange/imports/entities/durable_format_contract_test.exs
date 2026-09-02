defmodule Storyarn.Projects.Imports.DurableFormatContractTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Imports.PlanCleanupRequest
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Repo

  @future_format "future_format"

  test "durable changesets accept opaque format ids without declaring support" do
    now = TimeHelpers.now()

    attempt_changeset =
      ProjectImportAttempt.ready_changeset(
        %ProjectImportAttempt{
          project_id: 1,
          user_id: 1,
          plan_cleanup_request_id: 1
        },
        %{
          status: "ready",
          stage: "parsed",
          format: @future_format,
          source_kind: "file",
          parser_version: "1",
          idempotency_key: String.duplicate("a", 64),
          plan_storage_key: "imports/plans/00000000-0000-0000-0000-000000000000.plan.enc",
          counts: %{},
          warning_codes: [],
          expires_at: now
        }
      )

    cleanup_changeset =
      PlanCleanupRequest.reservation_changeset(%PlanCleanupRequest{}, %{
        plan_storage_key: "imports/plans/00000000-0000-0000-0000-000000000001.plan.enc",
        format: @future_format,
        parser_version: "1",
        state: "reserved",
        cleanup_after: now
      })

    assert attempt_changeset.valid?
    assert cleanup_changeset.valid?
  end

  test "both durable schemas reject identifiers outside the shared technical shape" do
    for format <- ["FutureFormat", String.duplicate("a", 31), "future-format"] do
      attempt_changeset =
        ProjectImportAttempt.ready_changeset(%ProjectImportAttempt{}, %{
          format: format
        })

      cleanup_changeset =
        PlanCleanupRequest.reservation_changeset(%PlanCleanupRequest{}, %{
          format: format
        })

      assert "has invalid format" in errors_on(attempt_changeset).format or
               "should be at most 30 character(s)" in errors_on(attempt_changeset).format

      assert "has invalid format" in errors_on(cleanup_changeset).format or
               "should be at most 30 character(s)" in errors_on(cleanup_changeset).format
    end
  end

  test "the migrated database constraints use the same registry-neutral shape" do
    for name <- [
          "project_import_attempts_format_check",
          "import_plan_cleanup_requests_format_check"
        ] do
      %{rows: [[definition]]} =
        Repo.query!(
          "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = $1",
          [name]
        )

      assert definition =~ "^[a-z][a-z0-9_]{0,29}$"
      refute definition =~ "yarn"
      refute definition =~ "storyarn"
    end
  end
end
