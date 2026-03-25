defmodule Storyarn.Repo.Migrations.AddCompletedAmbientIdsToExplorationSessions do
  use Ecto.Migration

  def change do
    alter table(:exploration_sessions) do
      add :completed_ambient_ids, {:array, :integer}, default: []
    end
  end
end
