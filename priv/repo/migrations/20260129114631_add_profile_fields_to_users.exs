defmodule Storyarn.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :display_name, :string
      add :avatar_url, :string
    end
  end
end
