defmodule Storyarn.Repo.Migrations.MigrateTemplateSchemaToArray do
  @moduledoc """
  Migrates the template schema field from map format to array format.

  Old format (map - no guaranteed order):
    %{
      "age" => %{"type" => "integer", "label" => "Age"},
      "bio" => %{"type" => "text", "label" => "Biography"}
    }

  New format (array - preserves order for drag-and-drop):
    [
      %{"name" => "age", "type" => "integer", "label" => "Age", "required" => false},
      %{"name" => "bio", "type" => "text", "label" => "Biography", "required" => false}
    ]
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE entity_templates
    SET schema = (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'name', key,
            'type', COALESCE(value->>'type', 'string'),
            'label', COALESCE(value->>'label', key),
            'required', COALESCE((value->>'required')::boolean, false),
            'default', value->>'default',
            'description', value->>'description',
            'options', value->'options'
          )
          ORDER BY key
        ),
        '[]'::jsonb
      )
      FROM jsonb_each(entity_templates.schema)
    )
    WHERE schema IS NOT NULL AND schema != '{}'::jsonb
    """)

    # For templates with empty or null schema, ensure they have an empty array
    execute("""
    UPDATE entity_templates
    SET schema = '[]'::jsonb
    WHERE schema IS NULL OR schema = '{}'::jsonb
    """)
  end

  def down do
    execute("""
    UPDATE entity_templates
    SET schema = (
      SELECT COALESCE(
        jsonb_object_agg(
          elem->>'name',
          jsonb_build_object(
            'type', elem->>'type',
            'label', elem->>'label',
            'required', (elem->>'required')::boolean,
            'default', elem->>'default',
            'description', elem->>'description',
            'options', elem->'options'
          ) - 'name'
        ),
        '{}'::jsonb
      )
      FROM jsonb_array_elements(entity_templates.schema) AS elem
    )
    WHERE schema IS NOT NULL AND jsonb_typeof(schema) = 'array'
    """)

    # For templates with empty array, set to empty object
    execute("""
    UPDATE entity_templates
    SET schema = '{}'::jsonb
    WHERE schema = '[]'::jsonb
    """)
  end
end
