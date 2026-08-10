defmodule Storyarn.Repo.Migrations.AddRecoverableAssetTrash do
  use Ecto.Migration

  def change do
    alter table(:assets) do
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
      add :deletion_reason, :string
      add :deletion_generation, :bigint, null: false, default: 0
    end

    create index(:assets, [:deleted_by_id])

    create index(:assets, [:project_id, :deleted_at, :id],
             where: "deleted_at IS NOT NULL",
             name: :assets_project_trash_index
           )

    create index(:assets, [:deleted_at, :id],
             where: "deleted_at IS NOT NULL",
             name: :assets_trash_retention_index
           )

    create index(:localized_texts, [:vo_asset_id],
             where: "vo_asset_id IS NOT NULL",
             name: :localized_texts_vo_asset_id_index
           )

    create index(:scenes, [:background_asset_id],
             where: "background_asset_id IS NOT NULL",
             name: :scenes_background_asset_id_index
           )

    create index(:sheet_avatars, [:asset_id], name: :sheet_avatars_asset_id_index)
    create index(:block_gallery_images, [:asset_id], name: :block_gallery_images_asset_id_index)

    execute(
      """
      CREATE INDEX flow_nodes_audio_asset_id_index
      ON flow_nodes ((data->>'audio_asset_id'))
      WHERE data->>'audio_asset_id' IS NOT NULL
      """,
      "DROP INDEX flow_nodes_audio_asset_id_index"
    )

    create constraint(:assets, :assets_deletion_generation_non_negative,
             check: "deletion_generation >= 0"
           )

    create constraint(:assets, :assets_trash_state_shape,
             check: """
             (
               deleted_at IS NULL AND
               deleted_by_id IS NULL AND
               deletion_reason IS NULL
             ) OR (
               deleted_at IS NOT NULL AND
               deletion_reason IS NOT NULL AND
               deletion_reason IN ('user', 'snapshot_restore', 'system') AND
               deletion_generation > 0
             )
             """
           )
  end
end
