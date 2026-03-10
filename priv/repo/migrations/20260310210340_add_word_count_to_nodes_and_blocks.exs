defmodule Storyarn.Repo.Migrations.AddWordCountToNodesAndBlocks do
  use Ecto.Migration

  def change do
    alter table(:flow_nodes) do
      add :word_count, :integer, default: 0, null: false
    end

    alter table(:blocks) do
      add :word_count, :integer, default: 0, null: false
    end
  end
end
