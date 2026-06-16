defmodule Storyarn.Repo.Migrations.AddProjectTypeMetadataToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :project_type, :string
      add :project_subtype, :string
      add :project_type_other, :string
    end
  end
end
