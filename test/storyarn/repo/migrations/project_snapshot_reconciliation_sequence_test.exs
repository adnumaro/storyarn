defmodule Storyarn.Repo.Migrations.ProjectSnapshotReconciliationSequenceTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.BackfillSnapshotClaimReconciliationSequence

  @migration_dir Path.expand("../../../../priv/repo/migrations", __DIR__)
  @backfill_migration Path.join(
                        @migration_dir,
                        "20260806111000_backfill_snapshot_claim_reconciliation_sequence.exs"
                      )

  if !Code.ensure_loaded?(BackfillSnapshotClaimReconciliationSequence) do
    Code.require_file(@backfill_migration)
  end

  test "claim sequence rollout keeps the historical backfill out of table-rewriting DDL" do
    prepare = migration_source("20260806110000_prepare_snapshot_claim_reconciliation_sequence.exs")
    backfill = migration_source("20260806111000_backfill_snapshot_claim_reconciliation_sequence.exs")
    index = migration_source("20260806112000_index_snapshot_claim_reconciliation_sequence.exs")
    finalize = migration_source("20260806113000_finalize_snapshot_claim_reconciliation_sequence.exs")
    promote = migration_source("20260806114000_promote_snapshot_claim_reconciliation_identity.exs")
    inspection = migration_source("20260806120000_create_project_snapshot_reconciliation_inspections.exs")

    assert prepare =~ "ADD COLUMN reconciliation_sequence bigint"
    refute prepare =~ "ADD COLUMN reconciliation_sequence bigint GENERATED"
    refute prepare =~ "UPDATE snapshot_object_publication_claims"

    assert backfill =~ "@disable_ddl_transaction true"
    assert backfill =~ "WHERE reconciliation_sequence IS NULL"
    assert backfill =~ "object_prefix > $2"
    assert backfill =~ "LIMIT $1"
    refute backfill =~ ~s(COLLATE "C")
    refute backfill =~ "ALTER TABLE"

    assert index =~ "@disable_ddl_transaction true"
    assert index =~ "@disable_migration_lock true"
    assert index =~ "concurrently: true"

    assert finalize =~ "VALIDATE CONSTRAINT"
    assert finalize =~ "ALTER COLUMN reconciliation_sequence SET NOT NULL"
    assert promote =~ "ADD GENERATED ALWAYS AS IDENTITY"
    assert promote =~ "SELECT setval("

    refute inspection =~ "ADD COLUMN reconciliation_sequence"
  end

  test "claim sequence backfill keysets through preexisting rows in bounded batches" do
    Repo.query!("CREATE TEMP SEQUENCE storyarn_snapshot_claim_reconciliation_seq AS bigint")

    Repo.query!("""
    CREATE TEMP TABLE snapshot_object_publication_claims (
      object_prefix text PRIMARY KEY,
      reconciliation_sequence bigint
    )
    """)

    Repo.query!("""
    INSERT INTO snapshot_object_publication_claims (object_prefix)
    VALUES ('projects/1/a'), ('projects/1/b'), ('projects/1/c')
    """)

    backfill = BackfillSnapshotClaimReconciliationSequence

    assert [["projects/1/b", 2, 2]] = Repo.query!(backfill.batch_sql(), [2]).rows

    assert [["projects/1/c", 1, 1]] =
             Repo.query!(backfill.batch_sql("projects/1/b"), [2, "projects/1/b"]).rows

    assert [[nil, 0, 0]] = Repo.query!(backfill.batch_sql("projects/1/c"), [2, "projects/1/c"]).rows

    rows =
      Repo.query!("""
      SELECT object_prefix, reconciliation_sequence
      FROM snapshot_object_publication_claims
      ORDER BY object_prefix
      """).rows

    assert Enum.sort(Enum.map(rows, &List.last/1)) == [1, 2, 3]
    assert ["projects/1/c", 3] in rows
  end

  test "deployed claim sequence is a validated database-owned identity" do
    assert [["NO", "YES", "ALWAYS", nil]] =
             Repo.query!("""
             SELECT is_nullable, is_identity, identity_generation, column_default
             FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = 'snapshot_object_publication_claims'
               AND column_name = 'reconciliation_sequence'
             """).rows

    assert [[true, true]] =
             Repo.query!("""
             SELECT index.indisunique, index.indisvalid
             FROM pg_index AS index
             JOIN pg_class AS relation ON relation.oid = index.indexrelid
             WHERE relation.relname =
               'snapshot_object_publication_claims_reconciliation_sequence_inde'
             """).rows

    assert [[true]] =
             Repo.query!("""
             SELECT convalidated
             FROM pg_constraint
             WHERE conname = 'snapshot_object_publication_claims_reconciliation_sequence'
             """).rows

    assert [["public.storyarn_snapshot_claim_reconciliation_seq"]] =
             Repo.query!("""
             SELECT pg_get_serial_sequence(
               'snapshot_object_publication_claims',
               'reconciliation_sequence'
             )
             """).rows
  end

  test "run progress key ordering is pinned to the C collation" do
    assert [[definition]] =
             Repo.query!("""
             SELECT pg_get_functiondef(
               'storyarn_guard_project_snapshot_reconciliation_run()'::regprocedure
             )
             """).rows

    normalized = Regex.replace(~r/\s+/, definition, " ")

    assert normalized =~
             ~s(NEW.active_inventory_last_key COLLATE "C" < OLD.active_inventory_last_key COLLATE "C")

    assert normalized =~
             ~s(NEW.provider_last_key COLLATE "C" < OLD.provider_last_key COLLATE "C")
  end

  defp migration_source(filename) do
    @migration_dir
    |> Path.join(filename)
    |> File.read!()
  end
end
