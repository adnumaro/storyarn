defmodule Storyarn.Repo.Migrations.AddParentSequenceToFlowNodes do
  use Ecto.Migration

  def change do
    alter table(:flow_nodes) do
      add :parent_sequence_id, references(:flow_sequences, on_delete: :nilify_all)
    end

    create index(:flow_nodes, [:parent_sequence_id])
  end
end
