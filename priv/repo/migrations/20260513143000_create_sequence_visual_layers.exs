defmodule Storyarn.Repo.Migrations.CreateSequenceVisualLayers do
  @moduledoc """
  Replaces the single sequence background image fields with explicit
  visual layers owned by sequence flow nodes.

  The current sequence media data only exists in local demos, so this is
  intentionally not backward compatible.
  """
  use Ecto.Migration

  @visual_kinds ["backdrop", "character", "prop", "overlay"]
  @visual_slots ["full", "left", "center", "right", "custom"]
  @visual_fits ["cover", "contain", "fill"]
  @track_kinds ["music", "ambience", "sfx"]

  def up do
    execute(
      "ALTER TABLE flow_node_sequence_configs DROP CONSTRAINT IF EXISTS flow_node_sequence_configs_background_fit_check"
    )

    execute(
      "ALTER TABLE flow_node_sequence_configs DROP CONSTRAINT IF EXISTS flow_node_sequence_configs_background_position_check"
    )

    drop_if_exists index(:flow_node_sequence_configs, [:background_asset_id])

    alter table(:flow_node_sequence_configs) do
      remove_if_exists :background_fit, :string
      remove_if_exists :background_position, :string
      remove_if_exists :background_asset_id, :bigint
    end

    create table(:flow_node_sequence_visual_layers) do
      add :flow_node_id,
          references(:flow_nodes, on_delete: :delete_all),
          null: false

      add :asset_id, references(:assets, on_delete: :delete_all), null: false

      add :kind, :string, size: 16, null: false
      add :label, :string, size: 120
      add :z_index, :integer, null: false, default: 0
      add :slot, :string, size: 16, null: false, default: "custom"

      add :x, :float, null: false, default: 0.0
      add :y, :float, null: false, default: 0.0
      add :width, :float, null: false, default: 1.0
      add :height, :float, null: false, default: 1.0
      add :anchor_x, :float, null: false, default: 0.0
      add :anchor_y, :float, null: false, default: 0.0

      add :fit, :string, size: 8, null: false, default: "contain"
      add :opacity, :float, null: false, default: 1.0
      add :visible, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:flow_node_sequence_visual_layers, [:flow_node_id, :z_index, :id])
    create index(:flow_node_sequence_visual_layers, [:asset_id])

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      ADD CONSTRAINT flow_node_sequence_visual_layers_kind_check
      CHECK (kind IN (#{sql_list(@visual_kinds)}))
    """

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      ADD CONSTRAINT flow_node_sequence_visual_layers_slot_check
      CHECK (slot IN (#{sql_list(@visual_slots)}))
    """

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      ADD CONSTRAINT flow_node_sequence_visual_layers_fit_check
      CHECK (fit IN (#{sql_list(@visual_fits)}))
    """

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      ADD CONSTRAINT flow_node_sequence_visual_layers_geometry_check
      CHECK (
        x >= 0 AND x <= 1
        AND y >= 0 AND y <= 1
        AND width > 0 AND width <= 1
        AND height > 0 AND height <= 1
        AND anchor_x >= 0 AND anchor_x <= 1
        AND anchor_y >= 0 AND anchor_y <= 1
        AND opacity >= 0 AND opacity <= 1
      )
    """

    execute """
    CREATE OR REPLACE FUNCTION fn_validate_sequence_visual_layer_owner() RETURNS TRIGGER AS $$
    DECLARE
      owner_type text;
    BEGIN
      SELECT type INTO owner_type FROM flow_nodes WHERE id = NEW.flow_node_id;
      IF owner_type IS NULL THEN
        RAISE EXCEPTION 'flow_node_id % does not exist', NEW.flow_node_id;
      END IF;
      IF owner_type <> 'sequence' THEN
        RAISE EXCEPTION 'flow_node_sequence_visual_layers.flow_node_id must reference a sequence node; got type %', owner_type;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER trg_flow_node_sequence_visual_layers_validate_owner
    BEFORE INSERT OR UPDATE OF flow_node_id ON flow_node_sequence_visual_layers
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_sequence_visual_layer_owner();
    """

    execute "ALTER TABLE flow_node_sequence_tracks DROP CONSTRAINT IF EXISTS flow_node_sequence_tracks_kind_check"
    execute "DELETE FROM flow_node_sequence_tracks WHERE kind = 'background'"
    execute "UPDATE flow_node_sequence_tracks SET kind = 'ambience' WHERE kind = 'ambient'"

    execute """
    ALTER TABLE flow_node_sequence_tracks
      ADD CONSTRAINT flow_node_sequence_tracks_kind_check
      CHECK (kind IN (#{sql_list(@track_kinds)}))
    """
  end

  def down do
    execute "ALTER TABLE flow_node_sequence_tracks DROP CONSTRAINT IF EXISTS flow_node_sequence_tracks_kind_check"
    execute "UPDATE flow_node_sequence_tracks SET kind = 'ambient' WHERE kind = 'ambience'"

    execute """
    ALTER TABLE flow_node_sequence_tracks
      ADD CONSTRAINT flow_node_sequence_tracks_kind_check
      CHECK (kind IN ('background', 'music', 'ambient'))
    """

    execute(
      "DROP TRIGGER IF EXISTS trg_flow_node_sequence_visual_layers_validate_owner ON flow_node_sequence_visual_layers"
    )

    execute("DROP FUNCTION IF EXISTS fn_validate_sequence_visual_layer_owner()")

    drop table(:flow_node_sequence_visual_layers)

    alter table(:flow_node_sequence_configs) do
      add :background_asset_id, references(:assets, on_delete: :nilify_all)
      add :background_position, :string, size: 16
      add :background_fit, :string, size: 8
    end

    create index(:flow_node_sequence_configs, [:background_asset_id])

    execute """
    ALTER TABLE flow_node_sequence_configs
      ADD CONSTRAINT flow_node_sequence_configs_background_position_check
      CHECK (
        background_position IS NULL
        OR background_position IN ('top-left', 'top-center', 'top-right', 'center-left', 'center', 'center-right', 'bottom-left', 'bottom-center', 'bottom-right')
      )
    """

    execute """
    ALTER TABLE flow_node_sequence_configs
      ADD CONSTRAINT flow_node_sequence_configs_background_fit_check
      CHECK (
        background_fit IS NULL
        OR background_fit IN ('cover', 'contain', 'fill')
      )
    """
  end

  defp sql_list(values), do: Enum.map_join(values, ", ", fn v -> "'#{v}'" end)
end
