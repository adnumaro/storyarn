defmodule Storyarn.Repo.Migrations.AddCurrentVersionIdToFlowsAndScenes do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :current_version_id, references(:entity_versions, on_delete: :nilify_all)
    end

    alter table(:scenes) do
      add :current_version_id, references(:entity_versions, on_delete: :nilify_all)
    end

    create index(:flows, [:current_version_id])
    create index(:scenes, [:current_version_id])
  end
end
