defmodule Storyarn.Repo.Migrations.DeleteSlugLineNodes do
  use Ecto.Migration

  def up do
    execute "DELETE FROM flow_nodes WHERE type = 'slug_line'"
    # flow_connections cascade via ON DELETE CASCADE (source_node_id, target_node_id).
  end

  def down do
    # Not reversible — slug_line node type is permanently deleted.
    :ok
  end
end
