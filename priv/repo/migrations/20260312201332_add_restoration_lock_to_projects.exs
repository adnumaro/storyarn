defmodule Storyarn.Repo.Migrations.AddRestorationLockToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :restoration_in_progress, :boolean, default: false, null: false
      add :restoration_started_by_id, references(:users, on_delete: :nilify_all), null: true
      add :restoration_started_at, :utc_datetime, null: true
    end
  end
end
