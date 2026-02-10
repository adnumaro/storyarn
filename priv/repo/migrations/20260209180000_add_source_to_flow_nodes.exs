defmodule Storyarn.Repo.Migrations.AddSourceToFlowNodes do
  use Ecto.Migration

  def change do
    alter table(:flow_nodes) do
      add :source, :string, default: "manual", null: false
    end

    create index(:flow_nodes, [:source])
  end
end
