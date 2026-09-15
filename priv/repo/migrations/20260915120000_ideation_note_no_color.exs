defmodule Storyarn.Repo.Migrations.IdeationNoteNoColor do
  use Ecto.Migration

  # A text-only note now wears its colour on the words. Every note carried the
  # default card colour, which would suddenly tint their text: they start with
  # no colour instead, like every new note.
  def up do
    execute("""
    UPDATE ideation_ideas
    SET canvas = jsonb_set(canvas, '{color}', '"none"')
    WHERE canvas->>'shape' = 'plain' AND canvas->>'color' = 'yellow'
    """)
  end

  def down do
    execute("""
    UPDATE ideation_ideas
    SET canvas = jsonb_set(canvas, '{color}', '"yellow"')
    WHERE canvas->>'color' = 'none'
    """)
  end
end
