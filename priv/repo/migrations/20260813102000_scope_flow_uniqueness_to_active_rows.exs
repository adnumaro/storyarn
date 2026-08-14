defmodule Storyarn.Repo.Migrations.ScopeRestoreIdentitiesToActiveRows do
  @moduledoc """
  Scopes main-flow, language, and dialogue localization identities to active content.

  Exact snapshot restore keeps the displaced graph in recoverable trash while
  materializing the archived graph as the new active graph. Trashed rows must
  therefore retain their identities without blocking their active replacements.
  Activation triggers preserve the inverse invariant: at most one active main
  flow and one active dialogue localization ID per project.
  """

  use Ecto.Migration

  @dialogue_trigger :flow_nodes_dialogue_localization_id_unique
  @flow_activation_trigger :flows_dialogue_localization_id_unique_on_activation

  def up do
    lock_identity_contract()
    assert_no_active_dialogue_duplicates!()

    execute("DROP INDEX flows_project_id_is_main_index")

    execute("""
    CREATE UNIQUE INDEX flows_project_id_is_main_index
    ON flows (project_id, is_main)
    WHERE is_main = true AND deleted_at IS NULL
    """)

    replace_dialogue_contract(:active)

    execute("DROP INDEX project_languages_project_id_locale_code_index")
    execute("DROP INDEX project_languages_one_source")

    execute("""
    CREATE UNIQUE INDEX project_languages_project_id_locale_code_index
    ON project_languages (project_id, locale_code)
    WHERE archived_at IS NULL
    """)

    execute("""
    CREATE UNIQUE INDEX project_languages_one_source
    ON project_languages (project_id)
    WHERE is_source = true AND archived_at IS NULL
    """)
  end

  def down do
    lock_identity_contract()
    assert_historical_contract_representable!()

    execute("DROP INDEX project_languages_one_source")
    execute("DROP INDEX project_languages_project_id_locale_code_index")

    execute("""
    CREATE UNIQUE INDEX project_languages_project_id_locale_code_index
    ON project_languages (project_id, locale_code)
    """)

    execute("""
    CREATE UNIQUE INDEX project_languages_one_source
    ON project_languages (project_id)
    WHERE is_source = true
    """)

    replace_dialogue_contract(:historical)

    execute("DROP INDEX flows_project_id_is_main_index")

    execute("""
    CREATE UNIQUE INDEX flows_project_id_is_main_index
    ON flows (project_id, is_main)
    WHERE is_main = true
    """)
  end

  defp lock_identity_contract do
    repo().query!("LOCK TABLE flows, flow_nodes, project_languages IN ACCESS EXCLUSIVE MODE")
  end

  defp assert_no_active_dialogue_duplicates! do
    case repo().query!("""
         SELECT EXISTS (
           SELECT 1
           FROM flow_nodes AS node
           JOIN flows AS flow ON flow.id = node.flow_id
           WHERE flow.deleted_at IS NULL
             AND node.deleted_at IS NULL
             AND node.type = 'dialogue'
             AND NULLIF(node.data->>'localization_id', '') IS NOT NULL
           GROUP BY flow.project_id, node.data->>'localization_id'
           HAVING count(*) > 1
         )
         """).rows do
      [[false]] ->
        :ok

      [[true]] ->
        raise Ecto.MigrationError,
              "active dialogue localization IDs must be unique before the active-only cutover"
    end
  end

  defp assert_historical_contract_representable! do
    case repo().query!("""
         SELECT
           EXISTS (
             SELECT 1 FROM flows WHERE is_main = true
             GROUP BY project_id HAVING count(*) > 1
           ) OR EXISTS (
             SELECT 1
             FROM flow_nodes AS node
             JOIN flows AS flow ON flow.id = node.flow_id
             WHERE node.type = 'dialogue'
               AND NULLIF(node.data->>'localization_id', '') IS NOT NULL
             GROUP BY flow.project_id, node.data->>'localization_id'
             HAVING count(*) > 1
           ) OR EXISTS (
             SELECT 1 FROM project_languages
             GROUP BY project_id, locale_code HAVING count(*) > 1
           ) OR EXISTS (
             SELECT 1 FROM project_languages WHERE is_source = true
             GROUP BY project_id HAVING count(*) > 1
           )
         """).rows do
      [[false]] ->
        :ok

      [[true]] ->
        raise Ecto.MigrationError,
              "ScopeRestoreIdentitiesToActiveRows cannot be rolled back after active and trashed identities coexist"
    end
  end

  defp replace_dialogue_contract(:active) do
    repo().query!("DROP TRIGGER IF EXISTS #{@dialogue_trigger} ON flow_nodes")

    repo().query!("""
    CREATE OR REPLACE FUNCTION enforce_dialogue_localization_id_unique()
    RETURNS trigger AS $$
    DECLARE
      dialogue_project_id bigint;
      dialogue_flow_deleted_at timestamp(0) without time zone;
      dialogue_localization_id text;
    BEGIN
      IF NEW.type <> 'dialogue' OR NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
      END IF;

      dialogue_localization_id := NULLIF(NEW.data->>'localization_id', '');
      IF dialogue_localization_id IS NULL THEN
        RETURN NEW;
      END IF;

      SELECT project_id, deleted_at
      INTO dialogue_project_id, dialogue_flow_deleted_at
      FROM flows
      WHERE id = NEW.flow_id;

      IF dialogue_project_id IS NULL THEN
        RETURN NEW;
      END IF;

      PERFORM pg_advisory_xact_lock(4717000000000 + dialogue_project_id);

      IF dialogue_flow_deleted_at IS NOT NULL THEN
        RETURN NEW;
      END IF;

      IF EXISTS (
        SELECT 1
        FROM flow_nodes AS node
        JOIN flows AS flow ON flow.id = node.flow_id
        WHERE flow.project_id = dialogue_project_id
          AND flow.deleted_at IS NULL
          AND node.deleted_at IS NULL
          AND node.type = 'dialogue'
          AND node.data->>'localization_id' = dialogue_localization_id
          AND node.id IS DISTINCT FROM NEW.id
      ) THEN
        RAISE EXCEPTION 'dialogue localization_id must be unique within the project'
          USING ERRCODE = '23505',
                CONSTRAINT = 'flow_nodes_dialogue_localization_id_unique';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    repo().query!("""
    CREATE TRIGGER #{@dialogue_trigger}
    BEFORE INSERT OR UPDATE OF type, data, flow_id, deleted_at ON flow_nodes
    FOR EACH ROW EXECUTE FUNCTION enforce_dialogue_localization_id_unique()
    """)

    repo().query!("""
    CREATE OR REPLACE FUNCTION enforce_activated_flow_dialogue_localization_ids_unique()
    RETURNS trigger AS $$
    DECLARE
      duplicate_localization_id text;
    BEGIN
      IF OLD.deleted_at IS NULL OR NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
      END IF;

      PERFORM pg_advisory_xact_lock(4717000000000 + NEW.project_id);

      SELECT restored_node.data->>'localization_id'
      INTO duplicate_localization_id
      FROM flow_nodes AS restored_node
      WHERE restored_node.flow_id = NEW.id
        AND restored_node.deleted_at IS NULL
        AND restored_node.type = 'dialogue'
        AND NULLIF(restored_node.data->>'localization_id', '') IS NOT NULL
      GROUP BY restored_node.data->>'localization_id'
      HAVING count(*) > 1
      LIMIT 1;

      IF duplicate_localization_id IS NULL THEN
        SELECT restored_node.data->>'localization_id'
        INTO duplicate_localization_id
        FROM flow_nodes AS restored_node
        JOIN flow_nodes AS active_node
          ON active_node.type = 'dialogue'
         AND active_node.deleted_at IS NULL
         AND active_node.data->>'localization_id' =
             restored_node.data->>'localization_id'
        JOIN flows AS active_flow ON active_flow.id = active_node.flow_id
        WHERE restored_node.flow_id = NEW.id
          AND restored_node.deleted_at IS NULL
          AND restored_node.type = 'dialogue'
          AND NULLIF(restored_node.data->>'localization_id', '') IS NOT NULL
          AND active_flow.project_id = NEW.project_id
          AND active_flow.deleted_at IS NULL
          AND active_flow.id <> NEW.id
        LIMIT 1;
      END IF;

      IF duplicate_localization_id IS NOT NULL THEN
        RAISE EXCEPTION 'dialogue localization_id must be unique within the project'
          USING ERRCODE = '23505',
                CONSTRAINT = 'flow_nodes_dialogue_localization_id_unique';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    repo().query!("""
    CREATE TRIGGER #{@flow_activation_trigger}
    BEFORE UPDATE OF deleted_at ON flows
    FOR EACH ROW EXECUTE FUNCTION enforce_activated_flow_dialogue_localization_ids_unique()
    """)
  end

  defp replace_dialogue_contract(:historical) do
    repo().query!("DROP TRIGGER IF EXISTS #{@flow_activation_trigger} ON flows")

    repo().query!(
      "DROP FUNCTION IF EXISTS enforce_activated_flow_dialogue_localization_ids_unique()"
    )

    repo().query!("DROP TRIGGER IF EXISTS #{@dialogue_trigger} ON flow_nodes")

    repo().query!("""
    CREATE OR REPLACE FUNCTION enforce_dialogue_localization_id_unique()
    RETURNS trigger AS $$
    DECLARE
      dialogue_project_id bigint;
      dialogue_localization_id text;
    BEGIN
      IF NEW.type <> 'dialogue' THEN
        RETURN NEW;
      END IF;

      dialogue_localization_id := NULLIF(NEW.data->>'localization_id', '');
      IF dialogue_localization_id IS NULL THEN
        RETURN NEW;
      END IF;

      SELECT project_id INTO dialogue_project_id FROM flows WHERE id = NEW.flow_id;
      IF dialogue_project_id IS NULL THEN
        RETURN NEW;
      END IF;

      PERFORM pg_advisory_xact_lock(4717000000000 + dialogue_project_id);

      IF EXISTS (
        SELECT 1
        FROM flow_nodes AS node
        JOIN flows AS flow ON flow.id = node.flow_id
        WHERE flow.project_id = dialogue_project_id
          AND node.type = 'dialogue'
          AND node.data->>'localization_id' = dialogue_localization_id
          AND node.id IS DISTINCT FROM NEW.id
      ) THEN
        RAISE EXCEPTION 'dialogue localization_id must be unique within the project'
          USING ERRCODE = '23505',
                CONSTRAINT = 'flow_nodes_dialogue_localization_id_unique';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    repo().query!("""
    CREATE TRIGGER #{@dialogue_trigger}
    BEFORE INSERT OR UPDATE OF type, data, flow_id ON flow_nodes
    FOR EACH ROW EXECUTE FUNCTION enforce_dialogue_localization_id_unique()
    """)
  end
end
