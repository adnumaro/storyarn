defmodule Storyarn.Repo.Migrations.AddFlowNodeCompositionInheritance do
  use Ecto.Migration

  @layer_fields ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible)
  @track_fields ~w(position asset_id start_time end_time volume)

  def up do
    alter table(:flow_nodes) do
      add :composition_source_id, references(:flow_nodes, on_delete: :nilify_all)
    end

    create index(:flow_nodes, [:composition_source_id])

    alter table(:flow_node_sequence_visual_layers) do
      add :layer_key, :string, size: 64
      add :overridden_fields, {:array, :string}, null: false, default: []
      add :removed, :boolean, null: false, default: false
    end

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      DROP CONSTRAINT flow_node_sequence_visual_layers_asset_id_fkey,
      ALTER COLUMN asset_id DROP NOT NULL,
      ADD CONSTRAINT flow_node_sequence_visual_layers_asset_id_fkey
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE SET NULL
    """

    execute """
    UPDATE flow_node_sequence_visual_layers
    SET layer_key = 'layer-' || id::text,
        overridden_fields = ARRAY[#{sql_list(@layer_fields)}]::varchar[]
    """

    execute "ALTER TABLE flow_node_sequence_visual_layers ALTER COLUMN layer_key SET NOT NULL"

    create unique_index(:flow_node_sequence_visual_layers, [:flow_node_id, :layer_key])

    alter table(:flow_node_sequence_tracks) do
      add :track_key, :string, size: 64
      add :is_override, :boolean, null: false, default: false
      add :overridden_fields, {:array, :string}, null: false, default: []
      add :removed, :boolean, null: false, default: false
    end

    execute """
    UPDATE flow_node_sequence_tracks
    SET track_key = 'track-' || id::text,
        overridden_fields = ARRAY[#{sql_list(@track_fields)}]::varchar[]
    """

    execute "ALTER TABLE flow_node_sequence_tracks ALTER COLUMN track_key SET NOT NULL"

    drop unique_index(:flow_node_sequence_tracks, [:flow_node_id, :kind])

    create unique_index(:flow_node_sequence_tracks, [:flow_node_id, :track_key])

    create unique_index(:flow_node_sequence_tracks, [:flow_node_id, :kind],
             where: "is_override = false",
             name: :flow_node_sequence_tracks_local_kind_index
           )

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      ADD CONSTRAINT flow_node_sequence_visual_layers_overridden_fields_check
      CHECK (overridden_fields <@ ARRAY[#{sql_list(@layer_fields)}]::varchar[])
    """

    execute """
    ALTER TABLE flow_node_sequence_tracks
      ADD CONSTRAINT flow_node_sequence_tracks_overridden_fields_check
      CHECK (overridden_fields <@ ARRAY[#{sql_list(@track_fields)}]::varchar[])
    """

    execute """
    UPDATE flow_nodes
    SET composition_source_id = parent_id
    WHERE type IN ('sequence', 'dialogue') AND parent_id IS NOT NULL
    """

    replace_owner_validation_functions(["sequence", "dialogue"])
    create_composition_source_validation()
    create_composition_source_lifecycle_guard()
  end

  def down do
    # The old schema has no representation for dialogue-owned composition,
    # inherited patches, or tombstones. Abort instead of silently changing or
    # deleting authored content during a downgrade.
    execute """
    LOCK TABLE flow_nodes, flow_node_sequence_tracks, flow_node_sequence_visual_layers
    IN SHARE MODE
    """

    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM flow_nodes AS owner
        WHERE owner.type IN ('sequence', 'dialogue')
          AND owner.composition_source_id IS DISTINCT FROM owner.parent_id
      ) OR EXISTS (
        SELECT 1
        FROM flow_node_sequence_tracks AS track
        JOIN flow_nodes AS owner ON owner.id = track.flow_node_id
        WHERE owner.type <> 'sequence'
          OR track.is_override = true
          OR track.removed = true
          OR NOT (
            track.overridden_fields @> ARRAY[#{sql_list(@track_fields)}]::varchar[]
          )
      ) OR EXISTS (
        SELECT 1
        FROM flow_node_sequence_visual_layers AS layer
        JOIN flow_nodes AS owner ON owner.id = layer.flow_node_id
        WHERE owner.type <> 'sequence'
          OR layer.removed = true
          OR layer.asset_id IS NULL
          OR NOT (layer.overridden_fields @> ARRAY[#{sql_list(@layer_fields)}]::varchar[])
      ) OR EXISTS (
        WITH RECURSIVE composition_chain(owner_id, ancestor_id) AS (
          SELECT owner.id, owner.composition_source_id
          FROM flow_nodes AS owner
          WHERE owner.type IN ('sequence', 'dialogue')
            AND owner.composition_source_id IS NOT NULL

          UNION

          SELECT chain.owner_id, ancestor.composition_source_id
          FROM composition_chain AS chain
          JOIN flow_nodes AS ancestor ON ancestor.id = chain.ancestor_id
          WHERE ancestor.composition_source_id IS NOT NULL
        )
        SELECT 1
        FROM flow_node_sequence_visual_layers AS local_layer
        JOIN composition_chain AS chain ON chain.owner_id = local_layer.flow_node_id
        JOIN flow_node_sequence_visual_layers AS inherited_layer
          ON inherited_layer.flow_node_id = chain.ancestor_id
          AND inherited_layer.layer_key = local_layer.layer_key
      ) THEN
        RAISE EXCEPTION
          'cannot roll back sequence composition inheritance while non-representable composition resources exist';
      END IF;
    END;
    $$;
    """

    execute(
      "DROP TRIGGER IF EXISTS trg_flow_nodes_guard_composition_source_lifecycle ON flow_nodes"
    )

    execute("DROP FUNCTION IF EXISTS fn_guard_flow_node_composition_source_lifecycle()")

    execute("DROP TRIGGER IF EXISTS trg_flow_nodes_validate_composition_source ON flow_nodes")

    execute("DROP FUNCTION IF EXISTS fn_validate_flow_node_composition_source()")

    replace_owner_validation_functions(["sequence"])

    execute """
    ALTER TABLE flow_node_sequence_tracks
      DROP CONSTRAINT IF EXISTS flow_node_sequence_tracks_overridden_fields_check
    """

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      DROP CONSTRAINT IF EXISTS flow_node_sequence_visual_layers_overridden_fields_check
    """

    drop index(:flow_node_sequence_tracks, [:flow_node_id, :kind],
           name: :flow_node_sequence_tracks_local_kind_index
         )

    drop unique_index(:flow_node_sequence_tracks, [:flow_node_id, :track_key])

    create unique_index(:flow_node_sequence_tracks, [:flow_node_id, :kind])

    alter table(:flow_node_sequence_tracks) do
      remove :removed
      remove :overridden_fields
      remove :is_override
      remove :track_key
    end

    drop unique_index(:flow_node_sequence_visual_layers, [:flow_node_id, :layer_key])

    alter table(:flow_node_sequence_visual_layers) do
      remove :removed
      remove :overridden_fields
      remove :layer_key
    end

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      DROP CONSTRAINT flow_node_sequence_visual_layers_asset_id_fkey,
      ALTER COLUMN asset_id SET NOT NULL,
      ADD CONSTRAINT flow_node_sequence_visual_layers_asset_id_fkey
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
    """

    drop index(:flow_nodes, [:composition_source_id])

    alter table(:flow_nodes) do
      remove :composition_source_id
    end
  end

  defp replace_owner_validation_functions(owner_types) do
    types = sql_list(owner_types)

    execute """
    CREATE OR REPLACE FUNCTION fn_validate_sequence_track_owner() RETURNS TRIGGER AS $$
    DECLARE
      owner_type text;
    BEGIN
      SELECT type INTO owner_type FROM flow_nodes WHERE id = NEW.flow_node_id;
      IF owner_type IS NULL THEN
        RAISE EXCEPTION 'flow_node_id % does not exist', NEW.flow_node_id;
      END IF;
      IF owner_type NOT IN (#{types}) THEN
        RAISE EXCEPTION 'flow_node_sequence_tracks.flow_node_id must reference a composition owner; got type %', owner_type;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
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
      IF owner_type NOT IN (#{types}) THEN
        RAISE EXCEPTION 'flow_node_sequence_visual_layers.flow_node_id must reference a composition owner; got type %', owner_type;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  defp create_composition_source_validation do
    execute """
    CREATE OR REPLACE FUNCTION fn_validate_flow_node_composition_source() RETURNS TRIGGER AS $$
    DECLARE
      source_type text;
      source_flow_id bigint;
      source_deleted_at timestamp without time zone;
    BEGIN
      IF NEW.composition_source_id IS NULL THEN
        RETURN NEW;
      END IF;

      IF NEW.type NOT IN ('sequence', 'dialogue') THEN
        RAISE EXCEPTION 'only sequence and dialogue nodes can define a composition source';
      END IF;

      IF NEW.id = NEW.composition_source_id THEN
        RAISE EXCEPTION 'composition source cycle for flow_node_id %', NEW.id;
      END IF;

      SELECT type, flow_id, deleted_at
        INTO source_type, source_flow_id, source_deleted_at
      FROM flow_nodes
      WHERE id = NEW.composition_source_id;

      IF source_type IS NULL THEN
        RAISE EXCEPTION 'composition_source_id % does not exist', NEW.composition_source_id;
      END IF;

      IF source_type NOT IN ('sequence', 'dialogue') THEN
        RAISE EXCEPTION 'composition_source_id % must reference a sequence or dialogue node', NEW.composition_source_id;
      END IF;

      IF source_flow_id <> NEW.flow_id THEN
        RAISE EXCEPTION 'composition source must belong to the same flow';
      END IF;

      IF source_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'composition source must be active';
      END IF;

      IF EXISTS (
        WITH RECURSIVE source_chain(id, composition_source_id) AS (
          SELECT id, composition_source_id
          FROM flow_nodes
          WHERE id = NEW.composition_source_id

          UNION

          SELECT source.id, source.composition_source_id
          FROM flow_nodes AS source
          JOIN source_chain AS current
            ON source.id = current.composition_source_id
        )
        SELECT 1 FROM source_chain WHERE id = NEW.id
      ) THEN
        RAISE EXCEPTION 'composition source cycle for flow_node_id %', NEW.id;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER trg_flow_nodes_validate_composition_source
    BEFORE INSERT OR UPDATE OF composition_source_id, type, flow_id, deleted_at ON flow_nodes
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_flow_node_composition_source();
    """
  end

  defp create_composition_source_lifecycle_guard do
    execute """
    CREATE OR REPLACE FUNCTION fn_guard_flow_node_composition_source_lifecycle() RETURNS TRIGGER AS $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM flow_nodes AS dependent
        WHERE dependent.composition_source_id = OLD.id
          AND dependent.deleted_at IS NULL
      ) AND (
        (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
        OR NEW.type NOT IN ('sequence', 'dialogue')
        OR NEW.flow_id <> OLD.flow_id
      ) THEN
        RAISE EXCEPTION 'flow_node_id % is the composition source of active nodes', OLD.id;
      END IF;

      IF OLD.type = 'dialogue'
         AND NEW.type NOT IN ('sequence', 'dialogue')
         AND (
           OLD.composition_source_id IS NOT NULL
           OR EXISTS (
             SELECT 1 FROM flow_node_sequence_configs AS config
             WHERE config.flow_node_id = OLD.id
           )
           OR EXISTS (
             SELECT 1 FROM flow_node_sequence_tracks AS track
             WHERE track.flow_node_id = OLD.id
           )
           OR EXISTS (
             SELECT 1 FROM flow_node_sequence_visual_layers AS layer
             WHERE layer.flow_node_id = OLD.id
           )
           OR EXISTS (
             SELECT 1 FROM flow_nodes AS dependent
             WHERE dependent.composition_source_id = OLD.id
           )
         ) THEN
        RAISE EXCEPTION 'flow_node_id % cannot leave a composition owner type while composition state exists', OLD.id;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER trg_flow_nodes_guard_composition_source_lifecycle
    BEFORE UPDATE OF deleted_at, type, flow_id ON flow_nodes
    FOR EACH ROW
    EXECUTE FUNCTION fn_guard_flow_node_composition_source_lifecycle();
    """
  end

  defp sql_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
