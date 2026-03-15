defmodule Storyarn.Repo.Migrations.AddAmbientFlowTriggerConfig do
  use Ecto.Migration

  def change do
    alter table(:scene_ambient_flows) do
      add :trigger_config, :map, null: false, default: %{}
      add :priority, :integer, null: false, default: 0
    end

    alter table(:exploration_sessions) do
      add :completed_ambient_ids, {:array, :integer}, null: false, default: []
    end
  end
end
