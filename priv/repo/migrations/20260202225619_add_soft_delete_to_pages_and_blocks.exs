defmodule Storyarn.Repo.Migrations.AddSoftDeleteToPagesAndBlocks do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :deleted_at, :utc_datetime
    end

    alter table(:blocks) do
      add :deleted_at, :utc_datetime
    end

    # Index for efficient filtering of non-deleted pages
    create index(:pages, [:deleted_at])

    # Index for efficient filtering of non-deleted blocks
    create index(:blocks, [:deleted_at])

    # Partial index for listing deleted pages (trash view)
    create index(:pages, [:project_id, :deleted_at],
      where: "deleted_at IS NOT NULL",
      name: :pages_trash_index
    )
  end
end
