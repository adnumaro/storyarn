defmodule Storyarn.Repo.Migrations.IdeationRoundBands do
  use Ecto.Migration

  # Rounds become horizontal bands of the session canvas. Every session owns at
  # least one round, prepared and cancelled rounds disappear (they never held a
  # note) and note positions become relative to their round's header. A band is
  # as tall as its content, so nothing is stored about its height: existing
  # boards only get each round's notes packed under its header.
  @band_lifecycle """
  (status = 'active' AND started_at IS NOT NULL AND closed_at IS NULL) OR
  (status = 'closed' AND started_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= started_at)
  """
  @optional_lifecycle """
  (status IN ('planned', 'cancelled') AND started_at IS NULL AND closed_at IS NULL) OR
  (status = 'active' AND started_at IS NOT NULL AND closed_at IS NULL) OR
  (status = 'closed' AND started_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= started_at)
  """

  # Canvas units between a round header and the highest note it holds.
  @band_top 80

  def up do
    execute("DELETE FROM ideation_rounds WHERE status IN ('planned', 'cancelled')")

    execute("""
    ALTER TABLE ideation_rounds
      DROP CONSTRAINT ideation_rounds_lifecycle_valid,
      ADD CONSTRAINT ideation_rounds_lifecycle_valid CHECK (#{@band_lifecycle})
    """)

    alter table(:ideation_rounds) do
      modify :status, :string, null: false, default: "active"
    end

    execute("""
    INSERT INTO ideation_rounds (session_id, number, status, started_at, closed_at, inserted_at, updated_at)
    SELECT s.id, 1,
           CASE WHEN s.status = 'open' THEN 'active' ELSE 'closed' END,
           s.inserted_at,
           CASE WHEN s.status = 'open' THEN NULL ELSE s.inserted_at END,
           now(), now()
    FROM ideation_sessions s
    WHERE NOT EXISTS (SELECT 1 FROM ideation_rounds r WHERE r.session_id = s.id)
    """)

    # Notes written outside any round join the earliest round of their session.
    execute("""
    UPDATE ideation_ideas i SET round_id = r.id
    FROM (SELECT DISTINCT ON (session_id) id, session_id FROM ideation_rounds ORDER BY session_id, number) r
    WHERE r.session_id = i.session_id AND i.round_id IS NULL
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
      modify :status, :string, null: false, default: "planned"
    end
  end

  defp relayout do
    %{rows: sessions} = repo().query!("SELECT id FROM ideation_sessions ORDER BY id", [])
    Enum.each(sessions, fn [session_id] -> relayout_session(session_id) end)
  end

  # Each round's notes move up so the highest one sits @band_top under the
  # header; groups made of one round's notes follow them.
  defp relayout_session(session_id) do
    %{rows: tops} =
      repo().query!(
        """
        SELECT round_id, MIN((canvas->>'y')::float8) FROM ideation_ideas
        WHERE session_id = $1 AND round_id IS NOT NULL AND jsonb_typeof(canvas->'y') = 'number'
        GROUP BY round_id
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

    Enum.each(tops, fn [round_id, top] ->
      natural_top = trunc(Float.floor(top)) - @band_top

      repo().query!(
        """
        UPDATE ideation_ideas
        SET canvas = jsonb_set(canvas, '{y}', to_jsonb((canvas->>'y')::numeric - $1::numeric))
        WHERE round_id = $2 AND jsonb_typeof(canvas->'y') = 'number'
        """,
        [natural_top, round_id]
      )

      case Map.get(group_rounds, round_id, []) do
        [] ->
          :ok

        groups ->
          # A group's revisions keep matching its frame, as recovery expects.
          for table <- ~w(ideation_groups ideation_group_revisions),
              column = if(table == "ideation_groups", do: "id", else: "group_id") do
            repo().query!(
              """
              UPDATE #{table}
              SET canvas = jsonb_set(canvas, '{y}', to_jsonb((canvas->>'y')::numeric - $1::numeric))
              WHERE #{column} = ANY($2) AND jsonb_typeof(canvas->'y') = 'number'
              """,
              [natural_top, groups]
            )
          end
      end
    end)
  end
end
