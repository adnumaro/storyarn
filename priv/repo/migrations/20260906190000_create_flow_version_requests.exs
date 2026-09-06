defmodule Storyarn.Repo.Migrations.CreateFlowVersionRequests do
  use Ecto.Migration

  def change do
    create table(:flow_version_requests) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :version_id, references(:entity_versions, on_delete: :nilify_all)
      add :snapshot, :map, null: false
      add :title, :string
      add :description, :text
      add :is_auto, :boolean, null: false, default: false
      add :status, :string, null: false, default: "pending"
      timestamps(type: :utc_datetime)
    end

    create index(:flow_version_requests, [:flow_id, :status, :id])

    create unique_index(:flow_version_requests, [:flow_id],
             where: "is_auto = true AND status = 'pending'",
             name: :flow_version_requests_pending_auto_unique
           )

    create constraint(:flow_version_requests, :flow_version_requests_status,
             check: "status IN ('pending', 'completed', 'failed', 'skipped')"
           )
  end
end
