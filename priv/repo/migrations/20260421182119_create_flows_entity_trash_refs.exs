defmodule Storyarn.Repo.Migrations.CreateFlowsEntityTrashRefs do
  use Ecto.Migration

  def change do
    create table(:flows_entity_trash_refs) do
      add :source_type, :string, null: false
      add :source_id, :bigint, null: false
      add :source_field, :string, null: false

      add :target_sheet_id, references(:sheets, on_delete: :delete_all)
      add :target_asset_id, references(:assets, on_delete: :delete_all)
      add :target_flow_id, references(:flows, on_delete: :delete_all)
      add :target_flow_node_id, references(:flow_nodes, on_delete: :delete_all)
      add :target_flow_sequence_id, references(:flow_sequences, on_delete: :delete_all)
      add :target_sheet_avatar_id, references(:sheet_avatars, on_delete: :delete_all)

      add :inserted_at, :utc_datetime, null: false
    end

    create constraint(:flows_entity_trash_refs, :source_type_valid,
             check: "source_type IN ('flow_node', 'flow_sequence')"
           )

    create constraint(:flows_entity_trash_refs, :exactly_one_target,
             check: """
             (
               (CASE WHEN target_sheet_id IS NOT NULL THEN 1 ELSE 0 END) +
               (CASE WHEN target_asset_id IS NOT NULL THEN 1 ELSE 0 END) +
               (CASE WHEN target_flow_id IS NOT NULL THEN 1 ELSE 0 END) +
               (CASE WHEN target_flow_node_id IS NOT NULL THEN 1 ELSE 0 END) +
               (CASE WHEN target_flow_sequence_id IS NOT NULL THEN 1 ELSE 0 END) +
               (CASE WHEN target_sheet_avatar_id IS NOT NULL THEN 1 ELSE 0 END)
             ) = 1
             """
           )

    create index(:flows_entity_trash_refs, [:target_sheet_id])
    create index(:flows_entity_trash_refs, [:target_asset_id])
    create index(:flows_entity_trash_refs, [:target_flow_id])
    create index(:flows_entity_trash_refs, [:target_flow_node_id])
    create index(:flows_entity_trash_refs, [:target_flow_sequence_id])
    create index(:flows_entity_trash_refs, [:target_sheet_avatar_id])
    create index(:flows_entity_trash_refs, [:source_type, :source_id])
  end
end
