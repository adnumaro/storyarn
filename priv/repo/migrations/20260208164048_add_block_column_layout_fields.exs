defmodule Storyarn.Repo.Migrations.AddBlockColumnLayoutFields do
  use Ecto.Migration

  def change do
    alter table(:blocks) do
      add :column_group_id, :uuid
      add :column_index, :integer, default: 0
    end

    create index(:blocks, [:sheet_id, :column_group_id],
      where: "column_group_id IS NOT NULL",
      name: :blocks_sheet_column_group_index
    )
  end
end
