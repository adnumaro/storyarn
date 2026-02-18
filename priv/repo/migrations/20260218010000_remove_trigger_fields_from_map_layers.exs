defmodule Storyarn.Repo.Migrations.RemoveTriggerFieldsFromMapLayers do
  use Ecto.Migration

  def change do
    alter table(:map_layers) do
      remove :trigger_sheet
      remove :trigger_variable
      remove :trigger_value
    end
  end
end
