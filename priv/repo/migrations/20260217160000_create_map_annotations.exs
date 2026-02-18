defmodule Storyarn.Repo.Migrations.CreateMapAnnotations do
  use Ecto.Migration

  def change do
    create table(:map_annotations) do
      add :map_id, references(:maps, on_delete: :delete_all), null: false
      add :layer_id, references(:map_layers, on_delete: :nilify_all)
      add :text, :text, null: false
      add :position_x, :float, null: false
      add :position_y, :float, null: false
      add :font_size, :string, default: "md"
      add :color, :string
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:map_annotations, [:map_id, :layer_id])
  end
end
