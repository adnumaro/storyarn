defmodule Storyarn.Repo.Migrations.AddVersionControlSettings do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :auto_snapshots_enabled, :boolean, default: true, null: false
      add :auto_version_flows, :boolean, default: true, null: false
      add :auto_version_scenes, :boolean, default: true, null: false
      add :auto_version_sheets, :boolean, default: true, null: false
    end

    alter table(:project_snapshots) do
      add :is_auto, :boolean, default: false, null: false
    end
  end
end
