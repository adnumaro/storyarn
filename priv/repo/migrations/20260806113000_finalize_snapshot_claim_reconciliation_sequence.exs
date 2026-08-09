defmodule Storyarn.Repo.Migrations.FinalizeSnapshotClaimReconciliationSequence do
  use Ecto.Migration

  @positive_constraint "snapshot_object_publication_claims_reconciliation_sequence"
  @not_null_constraint "snapshot_object_publication_claims_reconciliation_sequence_not_null"

  def up do
    execute("""
    ALTER TABLE snapshot_object_publication_claims
    VALIDATE CONSTRAINT #{@positive_constraint}
    """)

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    VALIDATE CONSTRAINT #{@not_null_constraint}
    """)

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ALTER COLUMN reconciliation_sequence SET NOT NULL
    """)

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    DROP CONSTRAINT #{@not_null_constraint}
    """)
  end

  def down do
    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ALTER COLUMN reconciliation_sequence DROP NOT NULL
    """)
  end
end
