defmodule Storyarn.Repo.Migrations.AddVariableFieldsToBlocks do
  use Ecto.Migration

  def change do
    alter table(:blocks) do
      # All blocks are variables by default, mark as constant to exclude
      add :is_constant, :boolean, default: false, null: false
      # Auto-generated from label, slugified (e.g., "Health Points" -> "health_points")
      add :variable_name, :string
    end

    # Ensure unique variable names within a page
    create unique_index(:blocks, [:page_id, :variable_name],
             where: "variable_name IS NOT NULL AND deleted_at IS NULL",
             name: :blocks_page_variable_unique
           )
  end
end
