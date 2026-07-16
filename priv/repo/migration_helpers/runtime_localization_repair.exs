defmodule Storyarn.Repo.Migrations.RuntimeLocalizationRepair do
  @moduledoc false

  @runtime_id_pattern "^[A-Za-z0-9_-]{1,100}$"

  def lock_sql do
    """
    LOCK TABLE flows, flow_nodes, flow_connections, localized_texts, project_languages
    IN SHARE ROW EXCLUSIVE MODE
    """
  end

  def runtime_id_sql do
    [
      create_dialogue_mapping_table_sql(),
      create_dialogue_mapping_index_sql(),
      preserve_dialogue_ids_sql(),
      generate_dialogue_ids_sql(),
      update_dialogue_ids_sql(),
      create_response_mapping_table_sql(),
      create_response_reservations_table_sql(),
      preserve_response_ids_sql(),
      reserve_direct_response_pins_sql(),
      reserve_prefixed_response_pins_sql(),
      reserve_localized_response_fields_sql(),
      generate_response_ids_sql(),
      remap_connection_pins_sql(),
      remap_localized_response_fields_sql(),
      update_response_ids_sql()
    ]
  end

  def locale_sql do
    [
      delete_invalid_localized_text_locales_sql(),
      delete_invalid_project_language_locales_sql(),
      consolidate_localized_text_locales_sql(),
      consolidate_project_language_locales_sql(),
      "UPDATE localized_texts SET locale_code = lower(locale_code)",
      "UPDATE project_languages SET locale_code = lower(locale_code)"
    ]
  end

  defp create_dialogue_mapping_table_sql do
    """
    CREATE TEMP TABLE storyarn_runtime_dialogue_ids (
      node_id bigint PRIMARY KEY,
      project_id bigint NOT NULL,
      old_id text,
      new_id text NOT NULL
    ) ON COMMIT DROP
    """
  end

  defp create_dialogue_mapping_index_sql do
    """
    CREATE UNIQUE INDEX storyarn_runtime_dialogue_ids_unique
    ON storyarn_runtime_dialogue_ids (project_id, new_id)
    """
  end

  defp preserve_dialogue_ids_sql do
    """
    WITH dialogue_candidates AS (
      SELECT node.id AS node_id,
             flow.project_id,
             node.data->>'localization_id' AS localization_id
      FROM flow_nodes AS node
      JOIN flows AS flow ON flow.id = node.flow_id
      WHERE node.type = 'dialogue'
    ),
    ranked_dialogues AS (
      SELECT dialogue.*,
             row_number() OVER (
               PARTITION BY dialogue.project_id, dialogue.localization_id
               ORDER BY
                 CASE
                   WHEN dialogue.localization_id =
                        'dialogue_' || md5('legacy:' || dialogue.node_id::text)
                   THEN 1
                   ELSE 0
                 END,
                 dialogue.node_id
             ) AS duplicate_rank
      FROM dialogue_candidates AS dialogue
    )
    INSERT INTO storyarn_runtime_dialogue_ids (node_id, project_id, old_id, new_id)
    SELECT dialogue.node_id,
           dialogue.project_id,
           dialogue.localization_id,
           dialogue.localization_id
    FROM ranked_dialogues AS dialogue
    WHERE dialogue.localization_id ~ '#{@runtime_id_pattern}'
      AND dialogue.duplicate_rank = 1
    """
  end

  defp generate_dialogue_ids_sql do
    """
    DO $$
    DECLARE
      dialogue record;
      candidate text;
      attempt integer;
      inserted_rows integer;
    BEGIN
      FOR dialogue IN
        SELECT node.id AS node_id,
               flow.project_id,
               node.data->>'localization_id' AS old_id
        FROM flow_nodes AS node
        JOIN flows AS flow ON flow.id = node.flow_id
        LEFT JOIN storyarn_runtime_dialogue_ids AS mapping ON mapping.node_id = node.id
        WHERE node.type = 'dialogue'
          AND mapping.node_id IS NULL
        ORDER BY flow.project_id, node.id
      LOOP
        attempt := 0;

        LOOP
          candidate := 'dialogue_' || md5(
            'legacy:' || dialogue.node_id::text ||
            CASE WHEN attempt = 0 THEN '' ELSE ':' || attempt::text END
          );

          INSERT INTO storyarn_runtime_dialogue_ids (node_id, project_id, old_id, new_id)
          VALUES (dialogue.node_id, dialogue.project_id, dialogue.old_id, candidate)
          ON CONFLICT DO NOTHING;

          GET DIAGNOSTICS inserted_rows = ROW_COUNT;
          EXIT WHEN inserted_rows = 1;

          attempt := attempt + 1;
        END LOOP;
      END LOOP;
    END;
    $$
    """
  end

  defp update_dialogue_ids_sql do
    """
    UPDATE flow_nodes AS node
    SET data = jsonb_set(
      CASE
        WHEN jsonb_typeof(node.data) = 'object' THEN node.data
        ELSE '{}'::jsonb
      END,
      '{localization_id}',
      to_jsonb(mapping.new_id)
    )
    FROM storyarn_runtime_dialogue_ids AS mapping
    WHERE node.id = mapping.node_id
      AND mapping.old_id IS DISTINCT FROM mapping.new_id
    """
  end

  defp create_response_mapping_table_sql do
    """
    CREATE TEMP TABLE storyarn_runtime_response_ids (
      node_id bigint NOT NULL,
      ordinality bigint NOT NULL,
      old_id text,
      new_id text NOT NULL,
      PRIMARY KEY (node_id, ordinality),
      UNIQUE (node_id, new_id)
    ) ON COMMIT DROP
    """
  end

  defp create_response_reservations_table_sql do
    """
    CREATE TEMP TABLE storyarn_runtime_response_id_reservations (
      node_id bigint NOT NULL,
      reserved_id text NOT NULL,
      PRIMARY KEY (node_id, reserved_id)
    ) ON COMMIT DROP
    """
  end

  defp preserve_response_ids_sql do
    """
    WITH response_candidates AS (
      SELECT node.id AS node_id,
             response.value,
             response.ordinality,
             response.value->>'id' AS response_id
      FROM flow_nodes AS node
      CROSS JOIN LATERAL jsonb_array_elements(
        CASE
          WHEN jsonb_typeof(node.data->'responses') = 'array' THEN node.data->'responses'
          ELSE '[]'::jsonb
        END
      ) WITH ORDINALITY AS response(value, ordinality)
      WHERE node.type = 'dialogue'
        AND jsonb_typeof(response.value) = 'object'
    ),
    ranked_responses AS (
      SELECT response.*,
             row_number() OVER (
               PARTITION BY response.node_id, response.response_id
               ORDER BY
                 CASE
                   WHEN response.response_id = 'response_' || md5(
                     'legacy:' || response.node_id::text || ':' || response.ordinality::text
                   )
                   THEN 1
                   ELSE 0
                 END,
                 response.ordinality
             ) AS duplicate_rank
      FROM response_candidates AS response
    ),
    preserved AS (
      INSERT INTO storyarn_runtime_response_ids (
        node_id,
        ordinality,
        old_id,
        new_id
      )
      SELECT response.node_id,
             response.ordinality,
             response.response_id,
             response.response_id
      FROM ranked_responses AS response
      WHERE response.response_id ~ '#{@runtime_id_pattern}'
        AND response.duplicate_rank = 1
      RETURNING node_id, new_id
    )
    INSERT INTO storyarn_runtime_response_id_reservations (node_id, reserved_id)
    SELECT preserved.node_id, preserved.new_id
    FROM preserved
    ON CONFLICT DO NOTHING
    """
  end

  defp reserve_direct_response_pins_sql do
    """
    INSERT INTO storyarn_runtime_response_id_reservations (node_id, reserved_id)
    SELECT connection.source_node_id, connection.source_pin
    FROM flow_connections AS connection
    JOIN flow_nodes AS node ON node.id = connection.source_node_id
    WHERE node.type = 'dialogue'
      AND connection.source_pin ~ '#{@runtime_id_pattern}'
    ON CONFLICT DO NOTHING
    """
  end

  defp reserve_prefixed_response_pins_sql do
    """
    INSERT INTO storyarn_runtime_response_id_reservations (node_id, reserved_id)
    SELECT connection.source_node_id, substring(connection.source_pin FROM 6)
    FROM flow_connections AS connection
    JOIN flow_nodes AS node ON node.id = connection.source_node_id
    WHERE node.type = 'dialogue'
      AND left(connection.source_pin, 5) = 'resp_'
      AND substring(connection.source_pin FROM 6) ~ '#{@runtime_id_pattern}'
    ON CONFLICT DO NOTHING
    """
  end

  defp reserve_localized_response_fields_sql do
    """
    INSERT INTO storyarn_runtime_response_id_reservations (node_id, reserved_id)
    SELECT localized_text.source_id,
           substring(
             localized_text.source_field
             FROM '^response[.]([A-Za-z0-9_-]{1,100})[.]text$'
           )
    FROM localized_texts AS localized_text
    JOIN flow_nodes AS node ON node.id = localized_text.source_id
    WHERE node.type = 'dialogue'
      AND localized_text.source_type = 'flow_node'
      AND localized_text.source_field ~ '^response[.][A-Za-z0-9_-]{1,100}[.]text$'
    ON CONFLICT DO NOTHING
    """
  end

  defp generate_response_ids_sql do
    """
    DO $$
    DECLARE
      response_item record;
      candidate text;
      attempt integer;
      inserted_rows integer;
    BEGIN
      FOR response_item IN
        SELECT node.id AS node_id,
               response.ordinality,
               response.value->>'id' AS old_id
        FROM flow_nodes AS node
        CROSS JOIN LATERAL jsonb_array_elements(
          CASE
            WHEN jsonb_typeof(node.data->'responses') = 'array' THEN node.data->'responses'
            ELSE '[]'::jsonb
          END
        ) WITH ORDINALITY AS response(value, ordinality)
        LEFT JOIN storyarn_runtime_response_ids AS mapping
          ON mapping.node_id = node.id
         AND mapping.ordinality = response.ordinality
        WHERE node.type = 'dialogue'
          AND jsonb_typeof(response.value) = 'object'
          AND mapping.node_id IS NULL
        ORDER BY node.id, response.ordinality
      LOOP
        attempt := 0;

        LOOP
          candidate := 'response_' || md5(
            'legacy:' || response_item.node_id::text || ':' || response_item.ordinality::text ||
            CASE WHEN attempt = 0 THEN '' ELSE ':' || attempt::text END
          );

          INSERT INTO storyarn_runtime_response_id_reservations (node_id, reserved_id)
          VALUES (response_item.node_id, candidate)
          ON CONFLICT DO NOTHING;

          GET DIAGNOSTICS inserted_rows = ROW_COUNT;

          IF inserted_rows = 1 THEN
            INSERT INTO storyarn_runtime_response_ids (
              node_id,
              ordinality,
              old_id,
              new_id
            )
            VALUES (
              response_item.node_id,
              response_item.ordinality,
              response_item.old_id,
              candidate
            );

            EXIT;
          END IF;

          attempt := attempt + 1;
        END LOOP;
      END LOOP;
    END;
    $$
    """
  end

  defp remap_connection_pins_sql do
    """
    WITH response_remaps AS (
      SELECT DISTINCT ON (mapping.node_id, mapping.old_id)
             mapping.node_id,
             mapping.old_id,
             mapping.new_id
      FROM storyarn_runtime_response_ids AS mapping
      WHERE mapping.old_id IS NOT NULL
        AND mapping.old_id <> mapping.new_id
        AND NOT EXISTS (
          SELECT 1
          FROM storyarn_runtime_response_ids AS preserved
          WHERE preserved.node_id = mapping.node_id
            AND preserved.old_id = mapping.old_id
            AND preserved.new_id = preserved.old_id
        )
      ORDER BY mapping.node_id, mapping.old_id, mapping.ordinality
    ),
    connection_remaps AS (
      SELECT DISTINCT ON (connection.id)
             connection.id AS connection_id,
             CASE
               WHEN connection.source_pin = remap.old_id THEN remap.new_id
               ELSE 'resp_' || remap.new_id
             END AS new_source_pin
      FROM flow_connections AS connection
      JOIN response_remaps AS remap
        ON remap.node_id = connection.source_node_id
       AND connection.source_pin IN (remap.old_id, 'resp_' || remap.old_id)
      ORDER BY
        connection.id,
        CASE WHEN connection.source_pin = remap.old_id THEN 0 ELSE 1 END,
        remap.old_id
    )
    UPDATE flow_connections AS connection
    SET source_pin = remap.new_source_pin
    FROM connection_remaps AS remap
    WHERE connection.id = remap.connection_id
    """
  end

  defp remap_localized_response_fields_sql do
    """
    WITH response_remaps AS (
      SELECT DISTINCT ON (mapping.node_id, mapping.old_id)
             mapping.node_id,
             mapping.old_id,
             mapping.new_id
      FROM storyarn_runtime_response_ids AS mapping
      WHERE mapping.old_id IS NOT NULL
        AND mapping.old_id <> mapping.new_id
        AND NOT EXISTS (
          SELECT 1
          FROM storyarn_runtime_response_ids AS preserved
          WHERE preserved.node_id = mapping.node_id
            AND preserved.old_id = mapping.old_id
            AND preserved.new_id = preserved.old_id
        )
      ORDER BY mapping.node_id, mapping.old_id, mapping.ordinality
    )
    UPDATE localized_texts AS localized_text
    SET source_field = 'response.' || remap.new_id || '.text'
    FROM response_remaps AS remap
    WHERE localized_text.source_type = 'flow_node'
      AND localized_text.source_id = remap.node_id
      AND localized_text.source_field = 'response.' || remap.old_id || '.text'
    """
  end

  defp update_response_ids_sql do
    """
    UPDATE flow_nodes AS node
    SET data = jsonb_set(
      node.data,
      '{responses}',
      (
        SELECT jsonb_agg(
          CASE
            WHEN mapping.new_id IS NULL THEN response.value
            ELSE response.value || jsonb_build_object('id', mapping.new_id)
          END
          ORDER BY response.ordinality
        )
        FROM jsonb_array_elements(node.data->'responses')
          WITH ORDINALITY AS response(value, ordinality)
        LEFT JOIN storyarn_runtime_response_ids AS mapping
          ON mapping.node_id = node.id
         AND mapping.ordinality = response.ordinality
      )
    )
    WHERE node.type = 'dialogue'
      AND jsonb_typeof(node.data->'responses') = 'array'
      AND EXISTS (
        SELECT 1
        FROM storyarn_runtime_response_ids AS mapping
        WHERE mapping.node_id = node.id
      )
    """
  end

  defp delete_invalid_localized_text_locales_sql do
    """
    DELETE FROM localized_texts
    WHERE locale_code !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'
       OR locale_code ~ E'[\\r\\n]'
       OR char_length(locale_code) > 35
    """
  end

  defp delete_invalid_project_language_locales_sql do
    """
    DELETE FROM project_languages
    WHERE locale_code !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'
       OR locale_code ~ E'[\\r\\n]'
       OR char_length(locale_code) > 35
    """
  end

  defp consolidate_localized_text_locales_sql do
    """
    WITH ranked_localized_texts AS (
      SELECT localized_text.id,
             row_number() OVER (
               PARTITION BY
                 localized_text.source_type,
                 localized_text.source_id,
                 localized_text.source_field,
                 lower(localized_text.locale_code)
               ORDER BY
                 CASE localized_text.status
                   WHEN 'final' THEN 5
                   WHEN 'review' THEN 4
                   WHEN 'in_progress' THEN 3
                   WHEN 'draft' THEN 2
                   ELSE 1
                 END DESC,
                 (NULLIF(BTRIM(localized_text.translated_text), '') IS NOT NULL) DESC,
                 CASE localized_text.vo_status
                   WHEN 'approved' THEN 4
                   WHEN 'recorded' THEN 3
                   WHEN 'needed' THEN 2
                   ELSE 1
                 END DESC,
                 COALESCE(
                   localized_text.last_reviewed_at,
                   localized_text.last_translated_at,
                   localized_text.updated_at,
                   localized_text.inserted_at
                 ) DESC,
                 localized_text.id
             ) AS locale_rank
      FROM localized_texts AS localized_text
    )
    DELETE FROM localized_texts AS localized_text
    USING ranked_localized_texts AS ranked
    WHERE localized_text.id = ranked.id
      AND ranked.locale_rank > 1
    """
  end

  defp consolidate_project_language_locales_sql do
    """
    WITH ranked_project_languages AS (
      SELECT language.id,
             row_number() OVER (
               PARTITION BY language.project_id, lower(language.locale_code)
               ORDER BY
                 language.is_source DESC,
                 (language.archived_at IS NULL) DESC,
                 language.position,
                 language.id
             ) AS locale_rank
      FROM project_languages AS language
    )
    DELETE FROM project_languages AS language
    USING ranked_project_languages AS ranked
    WHERE language.id = ranked.id
      AND ranked.locale_rank > 1
    """
  end
end
