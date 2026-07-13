defmodule Storyarn.Repo.Migrations.AddDurableStorageCleanupRequests do
  use Ecto.Migration

  def change do
    create table(:storage_cleanup_requests) do
      add :storage_keys, {:array, :text}, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:storage_cleanup_requests, :storage_cleanup_requests_keys_not_empty,
             check: "cardinality(storage_keys) > 0"
           )

    create index(:storage_cleanup_requests, [:inserted_at, :id])

    create index(
             :project_template_installs,
             [:workspace_id, :status, desc: :completed_at, desc: :id],
             name: :template_installs_workspace_failure_feedback_idx
           )
  end
end
