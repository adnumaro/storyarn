defmodule Storyarn.Repo.Migrations.CreateMapTables do
  use Ecto.Migration

  def change do
    create table(:maps) do
      add :name, :string, null: false
      add :description, :text
      add :shortcut, :string
      add :width, :integer
      add :height, :integer
      add :default_zoom, :float, default: 1.0
      add :default_center_x, :float, default: 50.0
      add :default_center_y, :float, default: 50.0
      add :position, :integer, default: 0
      add :deleted_at, :utc_datetime

      # Relationships
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :parent_id, references(:maps, on_delete: :nilify_all)
      add :background_asset_id, references(:assets, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:maps, [:project_id])
    create index(:maps, [:project_id, :parent_id])
    create index(:maps, [:project_id, :parent_id, :position])
    create index(:maps, [:deleted_at])

    create unique_index(:maps, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL AND deleted_at IS NULL",
             name: :maps_project_shortcut_unique
           )

    # -------------------------------------------------------

    create table(:map_layers) do
      add :name, :string, null: false
      add :is_default, :boolean, default: false
      add :trigger_sheet, :string
      add :trigger_variable, :string
      add :trigger_value, :string
      add :position, :integer, default: 0
      add :visible, :boolean, default: true

      add :map_id, references(:maps, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:map_layers, [:map_id, :position])

    # -------------------------------------------------------

    create table(:map_zones) do
      add :name, :string, null: false
      add :vertices, :jsonb, null: false
      add :fill_color, :string
      add :border_color, :string
      add :border_width, :integer, default: 2
      add :border_style, :string, default: "solid"
      add :opacity, :float, default: 0.3
      add :target_type, :string
      add :target_id, :integer
      add :tooltip, :text
      add :position, :integer, default: 0

      add :map_id, references(:maps, on_delete: :delete_all), null: false
      add :layer_id, references(:map_layers, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:map_zones, [:map_id, :layer_id])
    create index(:map_zones, [:target_type, :target_id])

    # -------------------------------------------------------

    create table(:map_pins) do
      add :position_x, :float, null: false
      add :position_y, :float, null: false
      add :pin_type, :string, default: "location"
      add :icon, :string
      add :color, :string
      add :label, :string
      add :target_type, :string
      add :target_id, :integer
      add :tooltip, :text
      add :size, :string, default: "md"
      add :position, :integer, default: 0

      add :map_id, references(:maps, on_delete: :delete_all), null: false
      add :layer_id, references(:map_layers, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:map_pins, [:map_id, :layer_id])
    create index(:map_pins, [:target_type, :target_id])

    # -------------------------------------------------------

    create table(:map_connections) do
      add :line_style, :string, default: "solid"
      add :color, :string
      add :label, :string
      add :bidirectional, :boolean, default: true

      add :map_id, references(:maps, on_delete: :delete_all), null: false
      add :from_pin_id, references(:map_pins, on_delete: :delete_all), null: false
      add :to_pin_id, references(:map_pins, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:map_connections, [:map_id])
  end
end
