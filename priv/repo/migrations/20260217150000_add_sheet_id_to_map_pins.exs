defmodule Storyarn.Repo.Migrations.AddSheetIdToMapPins do
  use Ecto.Migration

  def change do
    alter table(:map_pins) do
      add :sheet_id, references(:sheets, on_delete: :nilify_all)
    end

    create index(:map_pins, [:sheet_id])
  end
end
