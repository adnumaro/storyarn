defmodule Storyarn.Repo.Migrations.IndexFlowNodeAvatarReferences do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:flow_nodes, ["(data->>'avatar_id')"],
             name: :flow_nodes_avatar_id_index,
             concurrently: true
           )
  end

  def down do
    drop_if_exists index(:flow_nodes, ["(data->>'avatar_id')"],
                     name: :flow_nodes_avatar_id_index,
                     concurrently: true
                   )
  end
end
