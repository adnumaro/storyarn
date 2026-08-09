defmodule Storyarn.Repo.Migrations.PromoteSnapshotClaimReconciliationIdentity do
  use Ecto.Migration

  @sequence "storyarn_snapshot_claim_reconciliation_seq"

  def up do
    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ALTER COLUMN reconciliation_sequence DROP DEFAULT
    """)

    execute("ALTER SEQUENCE #{@sequence} OWNED BY NONE")
    execute("DROP SEQUENCE #{@sequence}")

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ALTER COLUMN reconciliation_sequence
    ADD GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME #{@sequence})
    """)

    reset_identity_sequence()
    create_immutability_guard()
  end

  def down do
    drop_immutability_guard()

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ALTER COLUMN reconciliation_sequence DROP IDENTITY
    """)

    execute("CREATE SEQUENCE #{@sequence} AS bigint")
    reset_plain_sequence()

    execute("""
    ALTER TABLE snapshot_object_publication_claims
    ALTER COLUMN reconciliation_sequence
    SET DEFAULT nextval('#{@sequence}'::regclass)
    """)

    execute("""
    ALTER SEQUENCE #{@sequence}
    OWNED BY snapshot_object_publication_claims.reconciliation_sequence
    """)
  end

  defp reset_identity_sequence do
    execute("""
    SELECT setval(
      pg_get_serial_sequence(
        'snapshot_object_publication_claims',
        'reconciliation_sequence'
      ),
      COALESCE(
        (SELECT max(reconciliation_sequence) FROM snapshot_object_publication_claims),
        1
      ),
      EXISTS (SELECT 1 FROM snapshot_object_publication_claims)
    )
    """)
  end

  defp reset_plain_sequence do
    execute("""
    SELECT setval(
      '#{@sequence}'::regclass,
      COALESCE(
        (SELECT max(reconciliation_sequence) FROM snapshot_object_publication_claims),
        1
      ),
      EXISTS (SELECT 1 FROM snapshot_object_publication_claims)
    )
    """)
  end

  defp create_immutability_guard do
    execute("""
    CREATE FUNCTION storyarn_guard_snapshot_claim_reconciliation_sequence()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
    IF NEW.reconciliation_sequence IS DISTINCT FROM OLD.reconciliation_sequence THEN
      RAISE EXCEPTION 'snapshot publication claim reconciliation sequence is immutable'
        USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER snapshot_object_publication_claims_reconciliation_sequence_guard
    BEFORE UPDATE ON snapshot_object_publication_claims
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_snapshot_claim_reconciliation_sequence()
    """)
  end

  defp drop_immutability_guard do
    execute("""
    DROP TRIGGER snapshot_object_publication_claims_reconciliation_sequence_guard
    ON snapshot_object_publication_claims
    """)

    execute("DROP FUNCTION storyarn_guard_snapshot_claim_reconciliation_sequence()")
  end
end
