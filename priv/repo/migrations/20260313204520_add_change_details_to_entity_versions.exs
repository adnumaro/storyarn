defmodule Storyarn.Repo.Migrations.AddChangeDetailsToEntityVersions do
  use Ecto.Migration

  def change do
    alter table(:entity_versions) do
      add :change_details, :map
    end
  end
end
