defmodule Storyarn.Repo.Migrations.NormalizeHubNodeColors do
  use Ecto.Migration

  @legacy_color_sql """
  CASE data->>'color'
    WHEN 'purple' THEN '#8b5cf6'
    WHEN 'blue' THEN '#3b82f6'
    WHEN 'green' THEN '#22c55e'
    WHEN 'yellow' THEN '#f59e0b'
    WHEN 'amber' THEN '#f59e0b'
    WHEN 'red' THEN '#ef4444'
    WHEN 'pink' THEN '#ec4899'
    WHEN 'orange' THEN '#f97316'
    WHEN 'cyan' THEN '#06b6d4'
  END
  """

  @legacy_colors "'purple', 'blue', 'green', 'yellow', 'amber', 'red', 'pink', 'orange', 'cyan'"

  def up do
    execute("""
    UPDATE flow_nodes
    SET data = jsonb_set(data, '{color}', to_jsonb((#{@legacy_color_sql})::text))
    WHERE type = 'hub'
      AND data->>'color' IN (#{@legacy_colors})
    """)

    execute("""
    UPDATE screenplay_elements
    SET data = jsonb_set(data, '{color}', to_jsonb((#{@legacy_color_sql})::text))
    WHERE type = 'hub_marker'
      AND data->>'color' IN (#{@legacy_colors})
    """)
  end

  def down do
    :ok
  end
end
