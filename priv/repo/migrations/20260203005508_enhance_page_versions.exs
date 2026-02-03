defmodule Storyarn.Repo.Migrations.EnhancePageVersions do
  use Ecto.Migration

  def change do
    # Add title and description to page_versions for manual versioning
    alter table(:page_versions) do
      add :title, :string
      add :description, :text
    end

    # Add current_version_id to pages to track active version
    alter table(:pages) do
      add :current_version_id, references(:page_versions, on_delete: :nilify_all)
    end

    create index(:pages, [:current_version_id])
  end
end
