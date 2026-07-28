defmodule Storyarn.Repo.Migrations.DropScreenplays do
  use Ecto.Migration

  @moduledoc """
  Removes the Screenplays feature.

  Four things go, in dependency order:

    1. `entity_references` rows whose source was a screenplay element. The
       column is a plain string with no FK, so nothing cascades them away.
    2. `screenplay_elements` and `screenplays`. Dropping the tables also drops
       their `trg_*_touch_project_activity` triggers.
    3. `storyarn_touch_project_activity_from_screenplay_id/0`, orphaned once
       `screenplay_elements` is gone.
    4. `flow_nodes.source`. Its only non-default value was `"screenplay_sync"`,
       written exclusively by `Screenplays.FlowSync`. Postgres drops
       `flow_nodes_source_index` along with the column.

  Irreversible: the screenplay content itself cannot be reconstructed, so
  `down/0` raises rather than recreating empty tables that would read as a
  successful rollback.
  """

  def up do
    execute("DELETE FROM entity_references WHERE source_type = 'screenplay_element'")

    drop table(:screenplay_elements)
    drop table(:screenplays)

    execute("DROP FUNCTION IF EXISTS storyarn_touch_project_activity_from_screenplay_id()")

    alter table(:flow_nodes) do
      remove :source
    end
  end

  def down do
    raise Ecto.MigrationError,
      message: "DropScreenplays is irreversible: screenplay content cannot be restored."
  end
end
