defmodule Storyarn.Repo.Migrations.AddSourceLocaleToWorkspaces do
  use Ecto.Migration

  def change do
    alter table(:workspaces) do
      add :source_locale, :string, size: 10, default: "en"
    end
  end
end
