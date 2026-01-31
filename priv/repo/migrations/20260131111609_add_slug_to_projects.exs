defmodule Storyarn.Repo.Migrations.AddSlugToProjects do
  use Ecto.Migration

  def up do
    alter table(:projects) do
      add :slug, :string
    end

    flush()

    # Generate slugs for existing projects
    execute """
    UPDATE projects
    SET slug = LOWER(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(name, '[^a-zA-Z0-9\\s-]', '', 'g'),
          '\\s+', '-', 'g'
        ),
        '-+', '-', 'g'
      )
    ) || '-' || SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 8)
    WHERE slug IS NULL
    """

    alter table(:projects) do
      modify :slug, :string, null: false
    end

    create unique_index(:projects, [:workspace_id, :slug])
  end

  def down do
    drop index(:projects, [:workspace_id, :slug])

    alter table(:projects) do
      remove :slug
    end
  end
end
