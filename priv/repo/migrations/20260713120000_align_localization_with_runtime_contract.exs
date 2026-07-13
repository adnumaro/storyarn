defmodule Storyarn.Repo.Migrations.AlignLocalizationWithRuntimeContract do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE flow_nodes
    SET data = jsonb_set(
      COALESCE(data, '{}'::jsonb),
      '{localization_id}',
      to_jsonb('dialogue_' || md5(random()::text || clock_timestamp()::text || id::text))
    )
    WHERE type = 'dialogue'
    """)

    execute("""
    UPDATE flow_nodes AS node
    SET data = jsonb_set(
      COALESCE(node.data, '{}'::jsonb),
      '{responses}',
      COALESCE(
        (
          SELECT jsonb_agg(
            response.value || jsonb_build_object(
              'id',
              'response_' || md5(
                random()::text || clock_timestamp()::text || node.id::text || response.ordinality::text
              )
            )
            ORDER BY response.ordinality
          )
          FROM jsonb_array_elements(
            CASE
              WHEN jsonb_typeof(node.data->'responses') = 'array' THEN node.data->'responses'
              ELSE '[]'::jsonb
            END
          ) WITH ORDINALITY AS response(value, ordinality)
          WHERE jsonb_typeof(response.value) = 'object'
        ),
        '[]'::jsonb
      )
    )
    WHERE node.type = 'dialogue'
    """)

    execute("""
    DELETE FROM localized_texts
    WHERE locale_code !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'
       OR char_length(locale_code) > 35
    """)

    execute("""
    DELETE FROM project_languages
    WHERE locale_code !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'
       OR char_length(locale_code) > 35
    """)

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

    create constraint(:localized_texts, :localized_texts_archive_reason_valid,
             check:
               "archive_reason IS NULL OR archive_reason IN ('source_deleted', 'source_field_removed', 'source_not_runtime', 'version_replaced')"
           )

    create constraint(:localized_texts, :localized_texts_locale_code_safe,
             check:
               "locale_code ~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$' AND char_length(locale_code) <= 35"
           )

    create constraint(:project_languages, :project_languages_locale_code_safe,
             check:
               "locale_code ~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$' AND char_length(locale_code) <= 35"
           )

    create index(:localized_texts, [:project_id, :locale_code, :status],
             where: "archived_at IS NULL",
             name: :localized_texts_active_status_index
           )

    create index(:localized_texts, [:project_id, :archived_at],
             name: :localized_texts_archive_index
           )
  end

  def down do
    drop index(:localized_texts, [:project_id, :archived_at],
           name: :localized_texts_archive_index
         )

    drop index(:localized_texts, [:project_id, :locale_code, :status],
           name: :localized_texts_active_status_index
         )

    drop constraint(:localized_texts, :localized_texts_archive_reason_valid)
    drop constraint(:localized_texts, :localized_texts_locale_code_safe)
    drop constraint(:project_languages, :project_languages_locale_code_safe)
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
    end
  end
end
