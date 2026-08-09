defmodule Storyarn.Repo.Migrations.PrepareSnapshotClaimReconciliationSequence do
  use Ecto.Migration

  @sequence "storyarn_snapshot_claim_reconciliation_seq"
  @positive_constraint "snapshot_object_publication_claims_reconciliation_sequence"
  @not_null_constraint "snapshot_object_publication_claims_reconciliation_sequence_not_null"

  def up do
    execute("CREATE SEQUENCE #{@sequence} AS bigint")

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ADD COLUMN reconciliation_sequence bigint
    """)

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ALTER COLUMN reconciliation_sequence
    SET DEFAULT nextval('#{@sequence}'::regclass)
    """)

    execute("""
    ALTER SEQUENCE #{@sequence}
    OWNED BY snapshot_object_publication_claims.reconciliation_sequence
    """)

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ADD CONSTRAINT #{@positive_constraint}
    CHECK (reconciliation_sequence > 0) NOT VALID
    """)

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ADD CONSTRAINT #{@not_null_constraint}
    CHECK (reconciliation_sequence IS NOT NULL) NOT VALID
    """)
  end

  def down do
    execute("""
    ALTER TABLE snapshot_object_publication_claims
    DROP COLUMN reconciliation_sequence
    """)
  end
end
