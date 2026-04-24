defmodule Storyarn.Repo.Migrations.UnifySequencesIntoFlowNodes do
  @moduledoc """
  Phase 1 of the flow relational refactor.

  Unifies `flow_sequences` into `flow_nodes` with `type='sequence'`. Creates
  a 1:1 config table `flow_node_sequence_configs` for sequence-specific
  fields (name/width/height). Introduces `flow_nodes.parent_id` self-FK to
  replace `flow_nodes.parent_sequence_id` and `flow_sequences.parent_id`,
  unifying the hierarchy under one mechanism.

  Installs five triggers that enforce invariants at DB level:
    * parent_id must reference a type='sequence' row.
    * flow_node_sequence_configs.flow_node_id must be type='sequence'.
    * flow_connections endpoints must not be type='sequence'.
    * Cannot change a node's type to 'sequence' if it has connections.
    * Soft-delete of a flow_node nilifies parent_id on its children.

  Data from `flow_sequences` is migrated. `flow_sequences.tracks` jsonb is
  discarded (empty in prod; a typed `flow_node_sequence_tracks` table is
  added in a later phase).
  """

  use Ecto.Migration

  @valid_types ~w(entry exit dialogue condition instruction hub jump subflow annotation sequence)

  def up do
    # ========================================================================
    # 1. Add parent_id self-FK to flow_nodes
    # ========================================================================
    alter table(:flow_nodes) do
      add :parent_id, references(:flow_nodes, on_delete: :nilify_all)
    end

    create index(:flow_nodes, [:parent_id])

    # ========================================================================
    # 2. Create flow_node_sequence_configs (1:1)
    # ========================================================================
    create table(:flow_node_sequence_configs, primary_key: false) do
      add :flow_node_id,
          references(:flow_nodes, on_delete: :delete_all),
          primary_key: true

      add :name, :string, size: 200, null: false
      add :width, :float, default: 300.0, null: false
      add :height, :float, default: 200.0, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:flow_node_sequence_configs, :flow_node_sequence_configs_name_length_check,
             check: "char_length(name) >= 1"
           )

    # ========================================================================
    # 3. Data migration: flow_sequences → flow_nodes + sequence_configs
    # ========================================================================
    execute("""
    CREATE TEMPORARY TABLE _seq_mapping (
      old_seq_id bigint PRIMARY KEY,
      new_node_id bigint NOT NULL
    ) ON COMMIT DROP
    """)

    execute("""
    DO $$
    DECLARE
      seq_rec RECORD;
      new_id bigint;
    BEGIN
      FOR seq_rec IN SELECT * FROM flow_sequences ORDER BY id LOOP
        INSERT INTO flow_nodes
          (type, flow_id, position_x, position_y, data, source, deleted_at, word_count, inserted_at, updated_at)
        VALUES
          ('sequence', seq_rec.flow_id, seq_rec.position_x, seq_rec.position_y,
           '{}'::jsonb, 'manual', seq_rec.deleted_at, 0,
           seq_rec.inserted_at, seq_rec.updated_at)
        RETURNING id INTO new_id;

        INSERT INTO _seq_mapping (old_seq_id, new_node_id) VALUES (seq_rec.id, new_id);

        INSERT INTO flow_node_sequence_configs
          (flow_node_id, name, width, height, inserted_at, updated_at)
        VALUES
          (new_id, seq_rec.name, seq_rec.width, seq_rec.height,
           seq_rec.inserted_at, seq_rec.updated_at);
      END LOOP;
    END $$
    """)

    # Map parent_id for non-sequence flow_nodes that had a parent_sequence_id
    execute("""
    UPDATE flow_nodes
    SET parent_id = m.new_node_id
    FROM _seq_mapping m
    WHERE flow_nodes.parent_sequence_id = m.old_seq_id
    """)

    # Map parent_id for the new sequence rows (from old flow_sequences.parent_id)
    execute("""
    UPDATE flow_nodes fn
    SET parent_id = m_out.new_node_id
    FROM _seq_mapping m_in
    JOIN flow_sequences fs ON fs.id = m_in.old_seq_id
    JOIN _seq_mapping m_out ON m_out.old_seq_id = fs.parent_id
    WHERE fn.id = m_in.new_node_id
    """)

    # ========================================================================
    # 4. Drop legacy columns / tables
    # ========================================================================
    drop index(:flow_nodes, [:parent_sequence_id])

    alter table(:flow_nodes) do
      remove :parent_sequence_id
    end

    # CASCADE drops the FK from flows_entity_trash_refs.target_flow_sequence_id
    # that would otherwise block the drop. The column itself persists as dead
    # weight until F7 drops flows_entity_trash_refs entirely.
    execute("DROP TABLE flow_sequences CASCADE")

    # ========================================================================
    # 5. Add CHECK constraint on flow_nodes.type
    # ========================================================================
    type_in_clause = Enum.map_join(@valid_types, ", ", fn t -> "'#{t}'" end)

    create constraint(:flow_nodes, :flow_nodes_type_check, check: "type IN (#{type_in_clause})")

    # ========================================================================
    # 6. Functions + triggers (blindaje DB-enforced)
    # ========================================================================

    # 6a. parent_id must reference a type='sequence' row
    execute("""
    CREATE OR REPLACE FUNCTION fn_validate_parent_is_sequence() RETURNS TRIGGER AS $$
    DECLARE
      parent_type text;
    BEGIN
      IF NEW.parent_id IS NULL THEN
        RETURN NEW;
      END IF;
      SELECT type INTO parent_type FROM flow_nodes WHERE id = NEW.parent_id;
      IF parent_type IS NULL THEN
        RAISE EXCEPTION 'parent_id % does not reference an existing flow_nodes row', NEW.parent_id;
      END IF;
      IF parent_type <> 'sequence' THEN
        RAISE EXCEPTION 'parent_id % references a % node; only sequence nodes can be parents', NEW.parent_id, parent_type;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_flow_nodes_validate_parent_is_sequence
    BEFORE INSERT OR UPDATE OF parent_id ON flow_nodes
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_parent_is_sequence();
    """)

    # 6b. sequence_config owner must be type='sequence'
    execute("""
    CREATE OR REPLACE FUNCTION fn_validate_sequence_config_owner() RETURNS TRIGGER AS $$
    DECLARE
      owner_type text;
    BEGIN
      SELECT type INTO owner_type FROM flow_nodes WHERE id = NEW.flow_node_id;
      IF owner_type IS NULL THEN
        RAISE EXCEPTION 'flow_node_id % does not exist', NEW.flow_node_id;
      END IF;
      IF owner_type <> 'sequence' THEN
        RAISE EXCEPTION 'flow_node_sequence_configs.flow_node_id must reference a sequence node; got type %', owner_type;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_flow_node_sequence_configs_validate_owner
    BEFORE INSERT OR UPDATE OF flow_node_id ON flow_node_sequence_configs
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_sequence_config_owner();
    """)

    # 6c. flow_connections endpoints must not be type='sequence'
    execute("""
    CREATE OR REPLACE FUNCTION fn_validate_connection_endpoints_not_sequence() RETURNS TRIGGER AS $$
    DECLARE
      src_type text;
      tgt_type text;
    BEGIN
      SELECT type INTO src_type FROM flow_nodes WHERE id = NEW.source_node_id;
      SELECT type INTO tgt_type FROM flow_nodes WHERE id = NEW.target_node_id;
      IF src_type = 'sequence' THEN
        RAISE EXCEPTION 'source_node_id % is a sequence; sequences cannot be connection endpoints', NEW.source_node_id;
      END IF;
      IF tgt_type = 'sequence' THEN
        RAISE EXCEPTION 'target_node_id % is a sequence; sequences cannot be connection endpoints', NEW.target_node_id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_flow_connections_validate_endpoints
    BEFORE INSERT OR UPDATE OF source_node_id, target_node_id ON flow_connections
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_connection_endpoints_not_sequence();
    """)

    # 6d. Cannot change type to 'sequence' if the node has connections
    execute("""
    CREATE OR REPLACE FUNCTION fn_prevent_type_change_to_sequence_with_connections() RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.type = 'sequence' AND OLD.type <> 'sequence' THEN
        IF EXISTS (
          SELECT 1 FROM flow_connections
          WHERE source_node_id = NEW.id OR target_node_id = NEW.id
        ) THEN
          RAISE EXCEPTION 'cannot change flow_node % to type=sequence: has existing connections', NEW.id;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_flow_nodes_prevent_type_change_to_sequence
    BEFORE UPDATE OF type ON flow_nodes
    FOR EACH ROW
    EXECUTE FUNCTION fn_prevent_type_change_to_sequence_with_connections();
    """)

    # 6e. Soft-delete fan-out: reparent children to grandparent when a node
    # soft-deletes. Previously nullified parent_id, but that "leaks" children
    # out of every containing sequence instead of just the deleted one. E.g.
    # deleting the inner sequence in `outer -> [inner -> [exit]]` should
    # leave `outer -> [exit]`, NOT `outer -> []` with exit at root.
    # OLD.parent_id is NULL for root-level nodes, preserving previous
    # behaviour in that case.
    execute("""
    CREATE OR REPLACE FUNCTION fn_flow_nodes_soft_delete_reparent_children() RETURNS TRIGGER AS $$
    BEGIN
      IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        UPDATE flow_nodes SET parent_id = OLD.parent_id WHERE parent_id = OLD.id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    DROP TRIGGER IF EXISTS trg_flow_nodes_soft_delete_nilify_parent ON flow_nodes;
    """)

    execute("""
    CREATE TRIGGER trg_flow_nodes_soft_delete_reparent_children
    AFTER UPDATE OF deleted_at ON flow_nodes
    FOR EACH ROW
    EXECUTE FUNCTION fn_flow_nodes_soft_delete_reparent_children();
    """)
  end

  def down do
    # Drop triggers + functions in reverse order
    execute("DROP TRIGGER IF EXISTS trg_flow_nodes_soft_delete_reparent_children ON flow_nodes")
    execute("DROP FUNCTION IF EXISTS fn_flow_nodes_soft_delete_reparent_children()")
    execute("DROP TRIGGER IF EXISTS trg_flow_nodes_soft_delete_nilify_parent ON flow_nodes")
    execute("DROP FUNCTION IF EXISTS fn_flow_nodes_soft_delete_nilify_parent()")

    execute("DROP TRIGGER IF EXISTS trg_flow_nodes_prevent_type_change_to_sequence ON flow_nodes")
    execute("DROP FUNCTION IF EXISTS fn_prevent_type_change_to_sequence_with_connections()")

    execute("DROP TRIGGER IF EXISTS trg_flow_connections_validate_endpoints ON flow_connections")
    execute("DROP FUNCTION IF EXISTS fn_validate_connection_endpoints_not_sequence()")

    execute(
      "DROP TRIGGER IF EXISTS trg_flow_node_sequence_configs_validate_owner ON flow_node_sequence_configs"
    )

    execute("DROP FUNCTION IF EXISTS fn_validate_sequence_config_owner()")

    execute("DROP TRIGGER IF EXISTS trg_flow_nodes_validate_parent_is_sequence ON flow_nodes")
    execute("DROP FUNCTION IF EXISTS fn_validate_parent_is_sequence()")

    # Drop type CHECK constraint
    drop constraint(:flow_nodes, :flow_nodes_type_check)

    # Recreate flow_sequences (data is NOT restored — destructive rollback)
    create table(:flow_sequences) do
      add :name, :string, null: false
      add :tracks, :map, default: %{}, null: false
      add :deleted_at, :utc_datetime
      add :position_x, :float, default: 0.0, null: false
      add :position_y, :float, default: 0.0, null: false
      add :width, :float, default: 300.0, null: false
      add :height, :float, default: 200.0, null: false
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :parent_id, references(:flow_sequences, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:flow_sequences, [:flow_id])
    create index(:flow_sequences, [:parent_id])

    create index(:flow_sequences, [:flow_id],
             where: "deleted_at IS NULL",
             name: :flow_sequences_active_flow_id_index
           )

    # Swap flow_nodes.parent_id → parent_sequence_id (data NOT restored)
    drop index(:flow_nodes, [:parent_id])

    alter table(:flow_nodes) do
      remove :parent_id
      add :parent_sequence_id, references(:flow_sequences, on_delete: :nilify_all)
    end

    create index(:flow_nodes, [:parent_sequence_id])

    # Delete type='sequence' rows (they have no counterpart in the restored flow_sequences)
    execute("DELETE FROM flow_nodes WHERE type = 'sequence'")

    # Drop flow_node_sequence_configs
    drop table(:flow_node_sequence_configs)
  end
end
