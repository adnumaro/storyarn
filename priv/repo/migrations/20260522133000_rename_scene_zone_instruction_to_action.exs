defmodule Storyarn.Repo.Migrations.RenameSceneZoneInstructionToAction do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE scene_zones
    SET action_type = 'action',
        action_data = CASE
          WHEN action_data IS NULL OR action_data = '{}'::jsonb THEN '{"assignments":[]}'::jsonb
          ELSE action_data
        END
    WHERE action_type IN ('none', 'navigate', 'instruction')
    """)

    execute("""
    UPDATE scene_zones
    SET action_type = 'walkable',
        action_data = '{}'::jsonb
    WHERE is_walkable = TRUE
      AND action_type = 'action'
      AND target_type IS NULL
      AND target_id IS NULL
      AND COALESCE(jsonb_array_length(action_data->'assignments'), 0) = 0
    """)

    execute("""
    UPDATE scene_zones
    SET target_type = NULL,
        target_id = NULL
    WHERE action_type != 'action'
    """)

    execute("""
    UPDATE scene_zones
    SET is_walkable = FALSE
    WHERE action_type != 'walkable'
    """)

    alter table(:scene_zones) do
      modify :action_type, :string, default: "action", null: false
      modify :action_data, :map, default: %{"assignments" => []}, null: false
    end
  end

  def down do
    execute("""
    UPDATE scene_zones
    SET action_type = 'instruction'
    WHERE action_type = 'action'
    """)

    alter table(:scene_zones) do
      modify :action_type, :string, default: "none", null: false
      modify :action_data, :map, default: %{}, null: false
    end
  end
end
