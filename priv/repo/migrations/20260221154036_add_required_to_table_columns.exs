defmodule Storyarn.Repo.Migrations.AddRequiredToTableColumns do
  use Ecto.Migration

  def change do
    alter table(:table_columns) do
      add :required, :boolean, null: false, default: false
    end
  end
end
