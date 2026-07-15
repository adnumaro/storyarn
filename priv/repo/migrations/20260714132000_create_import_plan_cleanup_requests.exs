defmodule Storyarn.Repo.Migrations.CreateImportPlanCleanupRequests do
  use Ecto.Migration

  def change do
    create table(:import_plan_cleanup_requests) do
      add :project_id, references(:projects, on_delete: :nilify_all), null: true
      add :plan_storage_key, :string, null: false
      add :format, :string, null: false
      add :parser_version, :string, null: false
      add :state, :string, null: false
      add :cleanup_after, :utc_datetime
      add :attempt_count, :integer, null: false, default: 0
      add :last_error_code, :string
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:import_plan_cleanup_requests, :import_plan_cleanup_requests_state_check,
             check: "state IN ('reserved', 'retained', 'pending', 'completed')"
           )

    create constraint(:import_plan_cleanup_requests, :import_plan_cleanup_requests_format_check,
             check: "format IN ('yarn', 'storyarn')"
           )

    create constraint(
             :import_plan_cleanup_requests,
             :import_plan_cleanup_requests_state_fields_check,
             check: """
             (state = 'reserved' AND cleanup_after IS NOT NULL AND completed_at IS NULL)
             OR (state = 'retained' AND cleanup_after IS NULL AND completed_at IS NULL)
             OR (state = 'pending' AND cleanup_after IS NOT NULL AND completed_at IS NULL)
             OR (state = 'completed' AND cleanup_after IS NULL AND completed_at IS NOT NULL)
             """
           )

    create constraint(
             :import_plan_cleanup_requests,
             :import_plan_cleanup_requests_attempt_count_check,
             check: "attempt_count >= 0"
           )

    create unique_index(:import_plan_cleanup_requests, [:plan_storage_key])
    create index(:import_plan_cleanup_requests, [:project_id])
    create index(:import_plan_cleanup_requests, [:state, :cleanup_after])
  end
end
