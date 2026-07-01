defmodule Storyarn.Repo.Migrations.AddSingleSceneLeaderIndex do
  use Ecto.Migration

  def up do
    execute """
    WITH ranked_leaders AS (
      SELECT
        id,
        row_number() OVER (
          PARTITION BY scene_id
          ORDER BY updated_at DESC NULLS LAST, inserted_at DESC NULLS LAST, id DESC
        ) AS rank
      FROM scene_pins
      WHERE is_leader = TRUE
    )
    UPDATE scene_pins
    SET is_leader = FALSE
    FROM ranked_leaders
    WHERE scene_pins.id = ranked_leaders.id
      AND ranked_leaders.rank > 1
    """

    create unique_index(:scene_pins, [:scene_id],
             where: "is_leader = TRUE",
             name: :scene_pins_single_leader_per_scene_index
           )
  end

  def down do
    drop_if_exists index(:scene_pins, [:scene_id],
                     name: :scene_pins_single_leader_per_scene_index
                   )
  end
end
