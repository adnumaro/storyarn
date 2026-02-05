defmodule Storyarn.Repo.Migrations.AddColorToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :color, :string
    end
  end
end
