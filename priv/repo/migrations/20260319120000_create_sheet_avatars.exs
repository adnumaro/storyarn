defmodule Storyarn.Repo.Migrations.CreateSheetAvatars do
  use Ecto.Migration

  def up do
    create table(:sheet_avatars) do
      add :name, :string
      add :notes, :text
      add :position, :integer, null: false, default: 0
      add :is_default, :boolean, null: false, default: false
      add :sheet_id, references(:sheets, on_delete: :delete_all), null: false
      add :asset_id, references(:assets, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sheet_avatars, [:sheet_id])
    create unique_index(:sheet_avatars, [:sheet_id, :asset_id])

    # Migrate existing avatar_asset_id to sheet_avatars
    execute """
    INSERT INTO sheet_avatars (sheet_id, asset_id, position, is_default, inserted_at, updated_at)
    SELECT id, avatar_asset_id, 0, true, NOW(), NOW()
    FROM sheets
    WHERE avatar_asset_id IS NOT NULL
    """
  end

  def down do
    drop table(:sheet_avatars)
  end
end
