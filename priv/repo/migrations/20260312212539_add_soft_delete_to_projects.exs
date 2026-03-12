defmodule Storyarn.Repo.Migrations.AddSoftDeleteToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :deleted_at, :utc_datetime, null: true
      add :deleted_by_id, references(:users, on_delete: :nilify_all), null: true
    end

    create index(:projects, [:workspace_id, :deleted_at])
  end
end
