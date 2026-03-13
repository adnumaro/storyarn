defmodule Storyarn.Repo.Migrations.AddLastEditedAtToDrafts do
  use Ecto.Migration

  def up do
    alter table(:drafts) do
      add :last_edited_at, :utc_datetime
    end

    # Backfill existing rows with inserted_at
    execute "UPDATE drafts SET last_edited_at = inserted_at"

    # Make non-nullable after backfill
    alter table(:drafts) do
      modify :last_edited_at, :utc_datetime, null: false
    end

    create index(:drafts, [:status, :last_edited_at])
  end

  def down do
    drop_if_exists index(:drafts, [:status, :last_edited_at])

    alter table(:drafts) do
      remove :last_edited_at
    end
  end
end
