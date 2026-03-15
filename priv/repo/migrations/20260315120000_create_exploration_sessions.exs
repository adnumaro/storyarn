defmodule Storyarn.Repo.Migrations.CreateExplorationSessions do
  use Ecto.Migration

  def change do
    create table(:exploration_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :scene_id, references(:scenes, on_delete: :nilify_all)
      add :variable_values, :map, default: %{}
      add :collected_ids, {:array, :string}, default: []
      add :player_positions, :map
      add :camera_state, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:exploration_sessions, [:user_id, :project_id])
    create index(:exploration_sessions, [:updated_at])
  end
end
