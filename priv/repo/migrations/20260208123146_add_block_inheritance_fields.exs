defmodule Storyarn.Repo.Migrations.AddBlockInheritanceFields do
  use Ecto.Migration

  def change do
    alter table(:blocks) do
      add :scope, :string, default: "self"
      add :inherited_from_block_id, references(:blocks, on_delete: :nilify_all)
      add :detached, :boolean, default: false
      add :required, :boolean, default: false
    end

    alter table(:sheets) do
      add :hidden_inherited_block_ids, {:array, :integer}, default: []
    end

    create index(:blocks, [:inherited_from_block_id])
    create index(:blocks, [:sheet_id, :inherited_from_block_id])

    create index(:blocks, [:scope],
             where: "scope = 'children'",
             name: :blocks_scope_children_index
           )
  end
end
