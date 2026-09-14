defmodule Storyarn.Repo.Migrations.IdeationRoundBands do
  use Ecto.Migration

  # Rounds become horizontal bands of the session canvas. Every session owns at
  # least one round, prepared and cancelled rounds disappear (they never held a
  # note), each round gets a canvas offset and note positions become relative to
  # their round's header. Existing boards are laid out band by band so nothing
  # overlaps after the change.
  @band_lifecycle """
  (status = 'active' AND started_at IS NOT NULL AND closed_at IS NULL) OR
  (status = 'closed' AND started_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= started_at)
  """
  @optional_lifecycle """
  (status IN ('planned', 'cancelled') AND started_at IS NULL AND closed_at IS NULL) OR
  (status = 'active' AND started_at IS NOT NULL AND closed_at IS NULL) OR
  (status = 'closed' AND started_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= started_at)
  """

  # Canvas units. A band keeps this much room below its lowest note, and an
  # empty band is this tall, so a new header never lands on existing notes.
  @band_top 80
  @band_gap 280
  @empty_band 320

  def up do
    execute("DELETE FROM ideation_rounds WHERE status IN ('planned', 'cancelled')")

    execute("""
    ALTER TABLE ideation_rounds
      DROP CONSTRAINT ideation_rounds_lifecycle_valid,
      ADD CONSTRAINT ideation_rounds_lifecycle_valid CHECK (#{@band_lifecycle})
    """)

    alter table(:ideation_rounds) do
      add :canvas_offset_y, :integer, null: false, default: 0
      modify :status, :string, null: false, default: "active"
    end

    execute("""
    INSERT INTO ideation_rounds (session_id, number, status, started_at, closed_at, canvas_offset_y, inserted_at, updated_at)
    SELECT s.id, 1,
           CASE WHEN s.status = 'open' THEN 'active' ELSE 'closed' END,
           s.inserted_at,
           CASE WHEN s.status = 'open' THEN NULL ELSE s.inserted_at END,
           0, now(), now()
    FROM ideation_sessions s
    WHERE NOT EXISTS (SELECT 1 FROM ideation_rounds r WHERE r.session_id = s.id)
    """)

    execute("""
    UPDATE ideation_ideas i SET round_id = r.id
    FROM ideation_rounds r
    WHERE r.session_id = i.session_id AND r.number = 1 AND i.round_id IS NULL
    """)

    flush()
    relayout()
  end

  def down do
    execute("""
    ALTER TABLE ideation_rounds
      DROP CONSTRAINT ideation_rounds_lifecycle_valid,
      ADD CONSTRAINT ideation_rounds_lifecycle_valid CHECK (#{@optional_lifecycle})
    """)

    alter table(:ideation_rounds) do
      remove :canvas_offset_y
      modify :status, :string, null: false, default: "planned"
    end
  end

  defp relayout do
    %{rows: sessions} = repo().query!("SELECT id FROM ideation_sessions ORDER BY id", [])
    Enum.each(sessions, fn [session_id] -> relayout_session(session_id) end)
  end

  defp relayout_session(session_id) do
    %{rows: rounds} =
      repo().query!("SELECT id FROM ideation_rounds WHERE session_id = $1 ORDER BY number", [
        session_id
      ])

    %{rows: ideas} =
      repo().query!(
        """
        SELECT round_id, (canvas->>'y')::float8 FROM ideation_ideas
        WHERE session_id = $1 AND round_id IS NOT NULL AND jsonb_typeof(canvas->'y') = 'number'
        """,
        [session_id]
      )

    %{rows: members} =
      repo().query!(
        """
        SELECT m.group_id, i.round_id FROM ideation_group_memberships m
        JOIN ideation_ideas i ON i.id = m.idea_id
        WHERE m.session_id = $1 AND m.removed_at IS NULL
        """,
        [session_id]
      )

    ys = Enum.group_by(ideas, fn [round_id, _] -> round_id end, fn [_, y] -> y end)

    group_rounds =
      members
      |> Enum.group_by(fn [group_id, _] -> group_id end, fn [_, round_id] -> round_id end)
      |> Enum.flat_map(fn {group_id, round_ids} ->
        case Enum.uniq(round_ids) do
          [round_id] -> [{group_id, round_id}]
          _mixed -> []
        end
      end)
      |> Enum.group_by(fn {_, round_id} -> round_id end, fn {group_id, _} -> group_id end)

    Enum.reduce(rounds, 0, fn [round_id], cursor ->
      case Map.get(ys, round_id, []) do
        [] ->
          set_offset(round_id, cursor)
          cursor + @empty_band

        values ->
          natural_top = trunc(Float.floor(Enum.min(values))) - @band_top
          offset = max(natural_top, cursor)
          set_offset(round_id, offset)

          repo().query!(
            """
            UPDATE ideation_ideas
            SET canvas = jsonb_set(canvas, '{y}', to_jsonb((canvas->>'y')::numeric - $1::numeric))
            WHERE round_id = $2 AND jsonb_typeof(canvas->'y') = 'number'
            """,
            [natural_top, round_id]
          )

          shift = offset - natural_top
          groups = Map.get(group_rounds, round_id, [])

          if shift > 0 and groups != [] do
            repo().query!(
              """
              UPDATE ideation_groups
              SET canvas = jsonb_set(canvas, '{y}', to_jsonb((canvas->>'y')::numeric + $1::numeric))
              WHERE id = ANY($2) AND jsonb_typeof(canvas->'y') = 'number'
              """,
              [shift, groups]
            )
          end

          offset + (trunc(Float.ceil(Enum.max(values))) - natural_top) + @band_gap
      end
    end)
  end

  defp set_offset(round_id, offset) do
    repo().query!("UPDATE ideation_rounds SET canvas_offset_y = $1 WHERE id = $2", [
      offset,
      round_id
    ])
  end
end
