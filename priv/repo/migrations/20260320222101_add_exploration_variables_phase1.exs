defmodule Storyarn.Repo.Migrations.AddExplorationVariablesPhase1 do
  use Ecto.Migration

  def up do
    # -- scene_pins: add new fields --
    alter table(:scene_pins) do
      add :shortcut, :string
      add :hidden, :boolean, default: false, null: false
      add :flow_id, references(:flows, on_delete: :nilify_all)
    end

    # Data migration: copy target_id → flow_id where target_type = 'flow'
    execute """
    UPDATE scene_pins SET flow_id = target_id
    WHERE target_type = 'flow' AND target_id IS NOT NULL
    """

    # Remove old target fields
    alter table(:scene_pins) do
      remove :target_type
      remove :target_id
    end

    create unique_index(:scene_pins, [:scene_id, :shortcut],
      where: "shortcut IS NOT NULL",
      name: :scene_pins_scene_id_shortcut_index
    )

    # -- scene_zones: add new fields --
    alter table(:scene_zones) do
      add :shortcut, :string
      add :hidden, :boolean, default: false, null: false
    end

    create unique_index(:scene_zones, [:scene_id, :shortcut],
      where: "shortcut IS NOT NULL",
      name: :scene_zones_scene_id_shortcut_index
    )
  end

  def down do
    drop_if_exists index(:scene_zones, [:scene_id, :shortcut],
                     name: :scene_zones_scene_id_shortcut_index)

    alter table(:scene_zones) do
      remove :shortcut
      remove :hidden
    end

    drop_if_exists index(:scene_pins, [:scene_id, :shortcut],
                     name: :scene_pins_scene_id_shortcut_index)

    # Restore old target fields
    alter table(:scene_pins) do
      add :target_type, :string
      add :target_id, :integer
    end

    # Data migration: copy flow_id back to target_type/target_id
    execute """
    UPDATE scene_pins SET target_type = 'flow', target_id = flow_id
    WHERE flow_id IS NOT NULL
    """

    alter table(:scene_pins) do
      remove :flow_id
      remove :hidden
      remove :shortcut
    end
  end
end
