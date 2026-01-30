defmodule Storyarn.Repo.Migrations.AddWorkspaceToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    create index(:projects, [:workspace_id])
  end
end
