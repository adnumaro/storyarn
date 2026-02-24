defmodule Storyarn.Repo.Migrations.CreateSceneTables do
  use Ecto.Migration

  def change do
    # -------------------------------------------------------
    # Scenes (formerly maps)
    # -------------------------------------------------------

    create table(:scenes) do
      add :name, :string, null: false
      add :description, :text
      add :shortcut, :string
      add :width, :integer
      add :height, :integer
      add :default_zoom, :float, default: 1.0
      add :default_center_x, :float, default: 50.0
      add :default_center_y, :float, default: 50.0
      add :scale_unit, :string
      add :scale_value, :float
      add :position, :integer, default: 0
      add :deleted_at, :utc_datetime

      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :parent_id, references(:scenes, on_delete: :nilify_all)
      add :background_asset_id, references(:assets, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:scenes, [:project_id])
    create index(:scenes, [:project_id, :parent_id])
    create index(:scenes, [:project_id, :parent_id, :position])
    create index(:scenes, [:deleted_at])

    create unique_index(:scenes, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL AND deleted_at IS NULL",
             name: :scenes_project_shortcut_unique
           )

    # -------------------------------------------------------
    # Scene Layers (no trigger fields, +fog, +locked)
    # -------------------------------------------------------

    create table(:scene_layers) do
      add :name, :string, null: false
      add :is_default, :boolean, default: false
      add :position, :integer, default: 0
      add :visible, :boolean, default: true
      add :fog_enabled, :boolean, default: false, null: false
      add :fog_color, :string, default: "#000000"
      add :fog_opacity, :float, default: 0.85

      add :scene_id, references(:scenes, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:scene_layers, [:scene_id, :position])
    create index(:scene_layers, [:scene_id])

    # -------------------------------------------------------
    # Scene Zones (+locked, +action, +condition)
    # -------------------------------------------------------

    create table(:scene_zones) do
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
      add :locked, :boolean, default: false, null: false
      add :action_type, :string, default: "navigate", null: false
      add :action_data, :map, default: %{}, null: false
      add :condition, :map, null: true
      add :condition_effect, :string, default: "hide"

      add :scene_id, references(:scenes, on_delete: :delete_all), null: false
      add :layer_id, references(:scene_layers, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:scene_zones, [:scene_id, :layer_id])
    create index(:scene_zones, [:target_type, :target_id])
    create index(:scene_zones, [:scene_id, :action_type])

    # -------------------------------------------------------
    # Scene Pins (+sheet_id, +icon_asset_id, +opacity, +locked, +condition, +action)
    # -------------------------------------------------------

    create table(:scene_pins) do
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
      add :opacity, :float, default: 1.0
      add :locked, :boolean, default: false, null: false
      add :condition, :map, null: true
      add :condition_effect, :string, default: "hide"
      add :action_type, :string, default: "none"
      add :action_data, :map, default: %{}

      add :scene_id, references(:scenes, on_delete: :delete_all), null: false
      add :layer_id, references(:scene_layers, on_delete: :nilify_all)
      add :sheet_id, references(:sheets, on_delete: :nilify_all)
      add :icon_asset_id, references(:assets, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:scene_pins, [:scene_id, :layer_id])
    create index(:scene_pins, [:target_type, :target_id])
    create index(:scene_pins, [:sheet_id])
    create index(:scene_pins, [:icon_asset_id])

    # -------------------------------------------------------
    # Scene Connections (+waypoints, +show_label, +line_width)
    # -------------------------------------------------------

    create table(:scene_connections) do
      add :line_style, :string, default: "solid"
      add :color, :string
      add :label, :string
      add :bidirectional, :boolean, default: true
      add :waypoints, :jsonb, default: "[]"
      add :show_label, :boolean, default: true, null: false
      add :line_width, :integer, default: 2

      add :scene_id, references(:scenes, on_delete: :delete_all), null: false
      add :from_pin_id, references(:scene_pins, on_delete: :delete_all), null: false
      add :to_pin_id, references(:scene_pins, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:scene_connections, [:scene_id])
    create index(:scene_connections, [:from_pin_id])
    create index(:scene_connections, [:to_pin_id])

    # -------------------------------------------------------
    # Scene Annotations (+locked)
    # -------------------------------------------------------

    create table(:scene_annotations) do
      add :scene_id, references(:scenes, on_delete: :delete_all), null: false
      add :layer_id, references(:scene_layers, on_delete: :nilify_all)
      add :text, :text, null: false
      add :position_x, :float, null: false
      add :position_y, :float, null: false
      add :font_size, :string, default: "md"
      add :color, :string
      add :position, :integer, default: 0
      add :locked, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:scene_annotations, [:scene_id, :layer_id])

    # -------------------------------------------------------
    # Add scene_id FK to flows (scene interaction model)
    # -------------------------------------------------------

    alter table(:flows) do
      add :scene_id, references(:scenes, on_delete: :nilify_all), null: true
    end

    create index(:flows, [:scene_id])
  end
end
