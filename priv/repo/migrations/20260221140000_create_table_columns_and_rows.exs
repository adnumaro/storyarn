defmodule Storyarn.Repo.Migrations.CreateTableColumnsAndRows do
  use Ecto.Migration

  def change do
    create table(:table_columns) do
      add :block_id, references(:blocks, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :type, :string, null: false, default: "number"
      add :is_constant, :boolean, null: false, default: false
      add :required, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:table_columns, [:block_id])
    create index(:table_columns, [:block_id, :position])
    create unique_index(:table_columns, [:block_id, :slug])

    create table(:table_rows) do
      add :block_id, references(:blocks, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :position, :integer, null: false, default: 0
      add :cells, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:table_rows, [:block_id])
    create index(:table_rows, [:block_id, :position])
    create unique_index(:table_rows, [:block_id, :slug])
  end
end
