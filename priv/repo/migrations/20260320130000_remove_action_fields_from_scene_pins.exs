defmodule Storyarn.Repo.Migrations.RemoveActionFieldsFromScenePins do
  use Ecto.Migration

  def change do
    alter table(:scene_pins) do
      remove :action_type, :string, default: "none"
      remove :action_data, :map, default: %{}
    end
  end
end
