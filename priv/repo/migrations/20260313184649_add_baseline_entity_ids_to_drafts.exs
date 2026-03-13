defmodule Storyarn.Repo.Migrations.AddBaselineEntityIdsToDrafts do
  use Ecto.Migration

  def change do
    alter table(:drafts) do
      add :baseline_entity_ids, :map, default: %{}
    end
  end
end
