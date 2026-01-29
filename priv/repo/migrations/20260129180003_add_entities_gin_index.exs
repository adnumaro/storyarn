defmodule Storyarn.Repo.Migrations.AddEntitiesGinIndex do
  use Ecto.Migration

  def change do
    execute(
      "CREATE INDEX entities_data_gin_idx ON entities USING gin (data jsonb_path_ops)",
      "DROP INDEX entities_data_gin_idx"
    )
  end
end
