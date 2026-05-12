defmodule Storyarn.Repo.Migrations.AddSequenceMediaConfig do
  @moduledoc """
  Extends `flow_node_sequence_configs` with background image settings
  (asset FK + CSS-like positioning + fit mode) and introduces
  `flow_node_sequence_tracks` — the relational replacement for the
  old `flow_sequences.tracks` jsonb (which was lost in phase 1 of the
  relational refactor).

  Scope:

    * `flow_node_sequence_configs.background_asset_id` (nullable FK
      to `assets(id)`, `ON DELETE SET NULL`): the image painted as the
      sequence backdrop during FlowPlay.
    * `flow_node_sequence_configs.background_position` (varchar, 9
      CSS-like values: `top-left`, `top-center`, ..., `bottom-right`):
      where to anchor the image within the sequence canvas when it
      doesn't cover the full bbox. Nullable; interpreted as `center`
      when null (no image).
    * `flow_node_sequence_configs.background_fit` (varchar, values
      `cover` | `contain` | `fill`): CSS `background-size` analogue.
      Nullable; interpreted as `cover` when null.
    * New table `flow_node_sequence_tracks`: one row per (sequence,
      kind) with `kind IN ('background', 'music', 'ambient')`. Each
      track has an optional asset + volume (0..1, three-decimal
      numeric matching the spec in `docs/features/flow-relational-refactor/REFACTOR.md`).
      The UNIQUE constraint on `(flow_node_id, kind)` enforces the
      "3 fixed slots per sequence" UX today; if we ever want
      stacked tracks per kind, drop the unique and start using the
      `position` column.
    * Trigger `fn_validate_sequence_track_owner`: mirror of
      `fn_validate_sequence_config_owner` — the `flow_node_id`
      referenced by a track must be `type='sequence'`. Blindamos en
      DB; la confianza genera errores en el futuro.

  Not in scope:

    * UI / panel — Slice C.
    * FlowPlay resolver — Slice D.
    * Backfill of old `flow_sequences.tracks` jsonb — that jsonb was
      empty in practice and was dropped in the phase 1 migration
      (see `priv/repo/migrations/20260422120000_unify_sequences_into_flow_nodes.exs`).
  """
  use Ecto.Migration

  @background_positions [
    "top-left",
    "top-center",
    "top-right",
    "center-left",
    "center",
    "center-right",
    "bottom-left",
    "bottom-center",
    "bottom-right"
  ]

  @background_fits ["cover", "contain", "fill"]

  @track_kinds ["background", "music", "ambient"]

  def up do
    # 1. Extend flow_node_sequence_configs with background media fields.
    alter table(:flow_node_sequence_configs) do
      add :background_asset_id, references(:assets, on_delete: :nilify_all)
      add :background_position, :string, size: 16
      add :background_fit, :string, size: 8
    end

    create index(:flow_node_sequence_configs, [:background_asset_id])

    # The CHECK constraints live as text rather than Ecto constraints so
    # the DB rejects invalid values regardless of code path.
    execute """
    ALTER TABLE flow_node_sequence_configs
      ADD CONSTRAINT flow_node_sequence_configs_background_position_check
      CHECK (
        background_position IS NULL
        OR background_position IN (#{positions_sql()})
      )
    """

    execute """
    ALTER TABLE flow_node_sequence_configs
      ADD CONSTRAINT flow_node_sequence_configs_background_fit_check
      CHECK (
        background_fit IS NULL
        OR background_fit IN (#{fits_sql()})
      )
    """

    # 2. Create flow_node_sequence_tracks.
    create table(:flow_node_sequence_tracks) do
      add :flow_node_id,
          references(:flow_nodes, on_delete: :delete_all),
          null: false

      add :kind, :string, size: 16, null: false
      add :position, :integer, null: false, default: 0

      add :asset_id, references(:assets, on_delete: :nilify_all)

      add :start_time, :decimal, precision: 10, scale: 3
      add :end_time, :decimal, precision: 10, scale: 3
      add :volume, :decimal, precision: 4, scale: 3, default: 1.0

      timestamps(type: :utc_datetime)
    end

    execute """
    ALTER TABLE flow_node_sequence_tracks
      ADD CONSTRAINT flow_node_sequence_tracks_kind_check
      CHECK (kind IN (#{kinds_sql()}))
    """

    execute """
    ALTER TABLE flow_node_sequence_tracks
      ADD CONSTRAINT flow_node_sequence_tracks_volume_range_check
      CHECK (volume IS NULL OR (volume >= 0 AND volume <= 1))
    """

    # One track per (sequence, kind) for now. See moduledoc for when/why
    # this could be dropped.
    create unique_index(:flow_node_sequence_tracks, [:flow_node_id, :kind])

    create index(:flow_node_sequence_tracks, [:flow_node_id, :kind, :position])
    create index(:flow_node_sequence_tracks, [:asset_id])

    # 3. Trigger — owner must be type='sequence'.
    execute("""
    CREATE OR REPLACE FUNCTION fn_validate_sequence_track_owner() RETURNS TRIGGER AS $$
    DECLARE
      owner_type text;
    BEGIN
      SELECT type INTO owner_type FROM flow_nodes WHERE id = NEW.flow_node_id;
      IF owner_type IS NULL THEN
        RAISE EXCEPTION 'flow_node_id % does not exist', NEW.flow_node_id;
      END IF;
      IF owner_type <> 'sequence' THEN
        RAISE EXCEPTION 'flow_node_sequence_tracks.flow_node_id must reference a sequence node; got type %', owner_type;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_flow_node_sequence_tracks_validate_owner
    BEFORE INSERT OR UPDATE OF flow_node_id ON flow_node_sequence_tracks
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_sequence_track_owner();
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS trg_flow_node_sequence_tracks_validate_owner ON flow_node_sequence_tracks"
    )

    execute("DROP FUNCTION IF EXISTS fn_validate_sequence_track_owner()")

    drop table(:flow_node_sequence_tracks)

    execute(
      "ALTER TABLE flow_node_sequence_configs DROP CONSTRAINT IF EXISTS flow_node_sequence_configs_background_fit_check"
    )

    execute(
      "ALTER TABLE flow_node_sequence_configs DROP CONSTRAINT IF EXISTS flow_node_sequence_configs_background_position_check"
    )

    drop index(:flow_node_sequence_configs, [:background_asset_id])

    alter table(:flow_node_sequence_configs) do
      remove :background_fit
      remove :background_position
      remove :background_asset_id
    end
  end

  defp positions_sql, do: sql_list(@background_positions)
  defp fits_sql, do: sql_list(@background_fits)
  defp kinds_sql, do: sql_list(@track_kinds)

  defp sql_list(values), do: Enum.map_join(values, ", ", fn v -> "'#{v}'" end)
end
