defmodule Storyarn.Repo.Migrations.AddTemplateVersionNotesAndPreview do
  use Ecto.Migration

  def change do
    alter table(:project_template_publications) do
      add :version_notes, :text
      add :preview, :map, null: false, default: %{}
    end

    alter table(:project_template_versions) do
      add :version_notes, :text
      add :preview, :map, null: false, default: %{}
    end
  end
end
