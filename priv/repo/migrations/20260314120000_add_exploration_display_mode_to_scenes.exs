defmodule Storyarn.Repo.Migrations.AddExplorationDisplayModeToScenes do
  use Ecto.Migration

  def change do
    alter table(:scenes) do
      add :exploration_display_mode, :string, default: "fit", null: false
    end
  end
end
