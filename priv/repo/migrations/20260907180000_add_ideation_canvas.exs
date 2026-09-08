defmodule Storyarn.Repo.Migrations.AddIdeationCanvas do
  use Ecto.Migration

  def change do
    alter table(:ideation_ideas) do
      add :canvas, :map, null: false, default: %{}
      add :deleted_at, :utc_datetime_usec
    end
  end
end
