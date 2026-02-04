defmodule Storyarn.Repo.Migrations.UnifyTreeModel do
  @moduledoc """
  Unifies the tree model between Pages and Flows.

  Changes:
  - Remove `is_folder` from flows (any flow can have children AND content)
  - Add `description` to pages (rich text for annotations, like flows already has)

  This creates consistency: both Pages and Flows follow the same pattern where
  any node can have children and content. The UI adapts based on what the node contains.
  """
  use Ecto.Migration

  def change do
    # Remove is_folder from flows - no longer needed
    # Any flow can have children AND nodes
    alter table(:flows) do
      remove :is_folder, :boolean, default: false
    end

    # Add description to pages - rich text for annotations
    # Flows already has this field
    alter table(:pages) do
      add :description, :text
    end
  end
end
