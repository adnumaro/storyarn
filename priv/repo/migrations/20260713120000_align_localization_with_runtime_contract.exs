Code.require_file(Path.expand("../migration_helpers/runtime_localization_repair.exs", __DIR__))

defmodule Storyarn.Repo.Migrations.AlignLocalizationWithRuntimeContract do
  use Ecto.Migration

  alias Storyarn.Repo.Migrations.RuntimeLocalizationRepair

  def up do
    execute(RuntimeLocalizationRepair.lock_sql())
    Enum.each(RuntimeLocalizationRepair.runtime_id_sql(), &execute/1)
    Enum.each(RuntimeLocalizationRepair.locale_sql(), &execute/1)

    alter table(:localized_texts) do
      modify :locale_code, :string, size: 35, null: false
    end

    alter table(:project_languages) do
      modify :locale_code, :string, size: 35, null: false
    end

    execute("""
    DELETE FROM localized_texts
    WHERE source_type NOT IN ('flow_node', 'block', 'sheet')
       OR (source_type = 'flow_node'
           AND source_field NOT IN ('text', 'stage_directions', 'menu_text', 'label')
           AND source_field !~ '^response\\.[A-Za-z0-9_-]{1,100}\\.text$')
       OR (source_type = 'block' AND source_field <> 'value.content')
       OR (source_type = 'sheet' AND source_field <> 'name')
    """)

    alter table(:localized_texts) do
      add :content_role, :string, null: false, default: "runtime_value"
      add :vo_eligible, :boolean, null: false, default: false
      add :archived_at, :utc_datetime
      add :archive_reason, :string
    end

    execute("""
    UPDATE localized_texts AS localized_text
    SET archived_at = COALESCE(localized_text.archived_at, CURRENT_TIMESTAMP),
        archive_reason = 'source_not_runtime'
    WHERE localized_text.source_type = 'block'
      AND NOT EXISTS (
        SELECT 1
        FROM blocks AS block
        JOIN sheets AS sheet ON sheet.id = block.sheet_id
        WHERE block.id = localized_text.source_id
          AND block.type IN ('text', 'rich_text')
          AND block.is_constant = false
          AND NULLIF(BTRIM(block.variable_name), '') IS NOT NULL
          AND block.deleted_at IS NULL
          AND sheet.deleted_at IS NULL
      )
    """)

    execute("""
    UPDATE localized_texts
    SET content_role = CASE
      WHEN source_type = 'block' THEN 'runtime_value'
      WHEN source_type = 'sheet' THEN 'speaker_name'
      WHEN source_field = 'text' THEN 'dialogue'
      WHEN source_field = 'stage_directions' THEN 'stage_direction'
      WHEN source_field = 'menu_text' THEN 'menu'
      WHEN source_field = 'label' THEN 'exit'
      WHEN source_field ~ '^response\\.[A-Za-z0-9_-]{1,100}\\.text$' THEN 'response'
      ELSE 'runtime_value'
    END,
    vo_eligible = source_type = 'flow_node'
      AND (source_field = 'text' OR source_field ~ '^response\\.[A-Za-z0-9_-]{1,100}\\.text$')
    """)

    execute("""
    UPDATE localized_texts
    SET vo_status = 'none', vo_asset_id = NULL
    WHERE vo_eligible = false
    """)

    create constraint(:localized_texts, :localized_texts_source_type_runtime,
             check: "source_type IN ('flow_node', 'block', 'sheet')"
           )

    create constraint(:localized_texts, :localized_texts_content_role_valid,
             check:
               "content_role IN ('dialogue', 'stage_direction', 'menu', 'response', 'exit', 'runtime_value', 'speaker_name')"
           )

    create constraint(:localized_texts, :localized_texts_source_field_runtime,
             check: """
             (source_type = 'block' AND source_field = 'value.content')
             OR (source_type = 'sheet' AND source_field = 'name')
             OR
             (source_type = 'flow_node' AND (
               source_field IN ('text', 'stage_directions', 'menu_text', 'label')
               OR source_field ~ '^response\\.[A-Za-z0-9_-]{1,100}\\.text$'
             ))
             """
           )

    create constraint(:localized_texts, :localized_texts_source_metadata_runtime,
             check: """
             (source_type = 'block' AND source_field = 'value.content'
               AND content_role = 'runtime_value' AND vo_eligible = false)
             OR
             (source_type = 'sheet' AND source_field = 'name'
               AND content_role = 'speaker_name' AND vo_eligible = false)
             OR
             (source_type = 'flow_node' AND source_field = 'text'
               AND content_role = 'dialogue' AND vo_eligible = true)
             OR
             (source_type = 'flow_node' AND source_field = 'stage_directions'
               AND content_role = 'stage_direction' AND vo_eligible = false)
             OR
             (source_type = 'flow_node' AND source_field = 'menu_text'
               AND content_role = 'menu' AND vo_eligible = false)
             OR
             (source_type = 'flow_node' AND source_field = 'label'
               AND content_role = 'exit' AND vo_eligible = false)
             OR
             (source_type = 'flow_node' AND source_field ~ '^response\\.[A-Za-z0-9_-]{1,100}\\.text$'
               AND content_role = 'response' AND vo_eligible = true)
             """
           )

    create constraint(:localized_texts, :localized_texts_vo_requires_eligible_source,
             check: "vo_eligible = true OR (vo_status = 'none' AND vo_asset_id IS NULL)"
           )

    create constraint(:localized_texts, :localized_texts_vo_status_valid,
             check: "vo_status IN ('none', 'needed', 'recorded', 'approved')"
           )

    create constraint(:localized_texts, :localized_texts_archive_reason_valid,
             check:
               "archive_reason IS NULL OR archive_reason IN ('source_deleted', 'source_field_removed', 'source_not_runtime', 'version_replaced')"
           )

    create constraint(:localized_texts, :localized_texts_locale_code_safe,
             check:
               "locale_code ~ '^[a-z]{2,3}(-[a-z0-9]{2,8})*$' AND locale_code !~ E'[\\r\\n]' AND char_length(locale_code) <= 35"
           )

    create constraint(:project_languages, :project_languages_locale_code_safe,
             check:
               "locale_code ~ '^[a-z]{2,3}(-[a-z0-9]{2,8})*$' AND locale_code !~ E'[\\r\\n]' AND char_length(locale_code) <= 35"
           )

    create index(:localized_texts, [:project_id, :locale_code, :status],
             where: "archived_at IS NULL",
             name: :localized_texts_active_status_index
           )

    create index(:localized_texts, [:project_id, :archived_at],
             name: :localized_texts_archive_index
           )

    execute("""
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

    execute("""
    CREATE TRIGGER flow_nodes_dialogue_localization_id_unique
    BEFORE INSERT OR UPDATE OF type, data, flow_id ON flow_nodes
    FOR EACH ROW EXECUTE FUNCTION enforce_dialogue_localization_id_unique()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS flow_nodes_dialogue_localization_id_unique ON flow_nodes")
    execute("DROP FUNCTION IF EXISTS enforce_dialogue_localization_id_unique()")

    drop index(:localized_texts, [:project_id, :archived_at],
           name: :localized_texts_archive_index
         )

    drop index(:localized_texts, [:project_id, :locale_code, :status],
           name: :localized_texts_active_status_index
         )

    drop constraint(:localized_texts, :localized_texts_archive_reason_valid)
    drop constraint(:localized_texts, :localized_texts_locale_code_safe)
    drop constraint(:project_languages, :project_languages_locale_code_safe)
    drop constraint(:localized_texts, :localized_texts_vo_status_valid)
    drop constraint(:localized_texts, :localized_texts_vo_requires_eligible_source)
    drop constraint(:localized_texts, :localized_texts_source_metadata_runtime)
    drop constraint(:localized_texts, :localized_texts_source_field_runtime)
    drop constraint(:localized_texts, :localized_texts_content_role_valid)
    drop constraint(:localized_texts, :localized_texts_source_type_runtime)

    alter table(:localized_texts) do
      remove :archive_reason
      remove :archived_at
      remove :vo_eligible
      remove :content_role
      modify :locale_code, :string, size: 10, null: false
    end

    alter table(:project_languages) do
      modify :locale_code, :string, size: 10, null: false
    end
  end
end
