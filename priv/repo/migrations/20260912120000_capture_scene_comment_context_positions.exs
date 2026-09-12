defmodule Storyarn.Repo.Migrations.CaptureSceneCommentContextPositions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION capture_scene_comment_position_at(
      target_type text, target_id bigint, target_scene_id bigint, target_inserted_at timestamp,
      origin_x float8, origin_y float8
    ) RETURNS void LANGUAGE plpgsql AS $$
    BEGIN
      IF origin_x IS NULL OR origin_y IS NULL
        OR NOT (origin_x > '-Infinity'::float8 AND origin_x < 'Infinity'::float8)
        OR NOT (origin_y > '-Infinity'::float8 AND origin_y < 'Infinity'::float8) THEN RETURN; END IF;

      UPDATE comment_threads
      SET position_x = GREATEST(0, LEAST(100, origin_x + context_offset_x)),
          position_y = GREATEST(0, LEAST(100, origin_y + context_offset_y))
      WHERE source_type = 'scene_canvas' AND context_type = target_type
        AND context_id = target_id::text AND container_id = target_scene_id
        AND context_inserted_at = target_inserted_at
        AND context_offset_x IS NOT NULL AND context_offset_y IS NOT NULL
        AND CASE target_type
          WHEN 'scene_pin' THEN context_scene_pin_id = target_id
          WHEN 'scene_zone' THEN context_scene_zone_id = target_id
          WHEN 'scene_connection' THEN context_scene_connection_id = target_id
          WHEN 'scene_annotation' THEN context_scene_annotation_id = target_id
          ELSE false END;
    END;
    $$
    """)

    execute("""
    CREATE FUNCTION capture_scene_connection_comment_position(target scene_connections)
    RETURNS void LANGUAGE plpgsql AS $$
    DECLARE origin_x float8; origin_y float8;
    BEGIN
      IF target.from_pin_id IS NOT NULL THEN
        SELECT position_x, position_y INTO origin_x, origin_y FROM scene_pins
        WHERE id = target.from_pin_id AND scene_id = target.scene_id;
      ELSIF jsonb_typeof(target.waypoints) = 'array' AND jsonb_array_length(target.waypoints) > 0 THEN
        origin_x := (target.waypoints->0->>'x')::float8;
        origin_y := (target.waypoints->0->>'y')::float8;
      ELSIF target.to_pin_id IS NOT NULL THEN
        SELECT position_x, position_y INTO origin_x, origin_y FROM scene_pins
        WHERE id = target.to_pin_id AND scene_id = target.scene_id;
      END IF;

      PERFORM capture_scene_comment_position_at(
        'scene_connection', target.id, target.scene_id, target.inserted_at, origin_x, origin_y);
    END;
    $$
    """)

    # Capture before cascades remove endpoint pins; the connection's own delete
    # trigger cannot resolve an endpoint that the initiating delete already removed.
    execute("""
    CREATE FUNCTION capture_scene_comment_context_position() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE
      origin_x float8; origin_y float8;
      connection scene_connections;
    BEGIN
      IF TG_TABLE_NAME = 'scene_connections' THEN
        PERFORM capture_scene_connection_comment_position(OLD);
        RETURN OLD;
      ELSIF TG_TABLE_NAME = 'scene_zones' THEN
        SELECT MIN((point->>'x')::float8), MIN((point->>'y')::float8)
        INTO origin_x, origin_y FROM jsonb_array_elements(OLD.vertices) AS point;
      ELSE
        origin_x := OLD.position_x;
        origin_y := OLD.position_y;
      END IF;

      PERFORM capture_scene_comment_position_at(
        TG_ARGV[0], OLD.id, OLD.scene_id, OLD.inserted_at, origin_x, origin_y);

      IF TG_TABLE_NAME = 'scene_pins' THEN
        FOR connection IN SELECT * FROM scene_connections
          WHERE scene_id = OLD.scene_id AND (from_pin_id = OLD.id OR to_pin_id = OLD.id)
        LOOP
          PERFORM capture_scene_connection_comment_position(connection);
        END LOOP;
      END IF;
      RETURN OLD;
    END;
    $$
    """)

    for {table, context} <- [
          {"scene_pins", "scene_pin"},
          {"scene_zones", "scene_zone"},
          {"scene_connections", "scene_connection"},
          {"scene_annotations", "scene_annotation"}
        ] do
      execute("""
      CREATE TRIGGER capture_scene_comment_context_position
      BEFORE DELETE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION capture_scene_comment_context_position('#{context}')
      """)
    end
  end

  def down do
    for table <- ~w(scene_pins scene_zones scene_connections scene_annotations) do
      execute("DROP TRIGGER capture_scene_comment_context_position ON #{table}")
    end

    execute("DROP FUNCTION capture_scene_comment_context_position()")
    execute("DROP FUNCTION capture_scene_connection_comment_position(scene_connections)")

    execute(
      "DROP FUNCTION capture_scene_comment_position_at(text, bigint, bigint, timestamp, float8, float8)"
    )
  end
end
