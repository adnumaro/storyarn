defmodule Storyarn.Repo.Migrations.LinkImportAttemptsToPlanCleanupRequests do
  use Ecto.Migration

  def change do
    alter table(:project_import_attempts) do
      add :plan_cleanup_request_id,
          references(:import_plan_cleanup_requests, on_delete: :nilify_all),
          null: true
    end

    create unique_index(:project_import_attempts, [:plan_cleanup_request_id])
  end
end
