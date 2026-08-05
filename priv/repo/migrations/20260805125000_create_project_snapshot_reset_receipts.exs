defmodule Storyarn.Repo.Migrations.CreateProjectSnapshotResetReceipts do
  use Ecto.Migration

  def up do
    create table(:project_snapshot_reset_receipts, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :workspace_id, :bigint, null: false
      add :plan_id, :uuid, null: false
      add :project_ids, {:array, :bigint}, null: false
      add :environment, :string, size: 128, null: false
      add :inventory_digest, :string, size: 64, null: false
      add :database_inventory_digest, :string, size: 64, null: false
      add :storage_namespace_fingerprint, :string, size: 64, null: false
      add :authorization_digest, :string, size: 64, null: false
      add :object_count, :bigint, null: false
      add :object_bytes, :bigint, null: false
      add :snapshot_row_count, :bigint, null: false
      add :entity_version_row_count, :bigint, null: false
      add :attempt_count, :bigint, null: false
      add :completed_at, :utc_datetime, null: false

      add :inserted_at, :utc_datetime,
        null: false,
        default: fragment("date_trunc('second', timezone('UTC', now()))::timestamp")
    end

    execute("""
    CREATE FUNCTION storyarn_valid_sorted_positive_bigints(value bigint[])
    RETURNS boolean AS $$
      SELECT
        array_position(value, NULL) IS NULL AND
        COALESCE((SELECT bool_and(project_id > 0) FROM unnest(value) AS ids(project_id)), TRUE) AND
        value = ARRAY(
          SELECT DISTINCT project_id
          FROM unnest(value) AS ids(project_id)
          ORDER BY project_id
        );
    $$ LANGUAGE sql IMMUTABLE STRICT;
    """)

    create constraint(
             :project_snapshot_reset_receipts,
             :project_snapshot_reset_receipts_project_ids,
             check: "storyarn_valid_sorted_positive_bigints(project_ids)"
           )

    create constraint(
             :project_snapshot_reset_receipts,
             :project_snapshot_reset_receipts_environment,
             check: "environment ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'"
           )

    create constraint(:project_snapshot_reset_receipts, :project_snapshot_reset_receipts_digests,
             check: """
             inventory_digest ~ '^[0-9a-f]{64}$' AND
             database_inventory_digest ~ '^[0-9a-f]{64}$' AND
             storage_namespace_fingerprint ~ '^[0-9a-f]{64}$' AND
             authorization_digest ~ '^[0-9a-f]{64}$'
             """
           )

    create constraint(:project_snapshot_reset_receipts, :project_snapshot_reset_receipts_counts,
             check: """
             workspace_id > 0 AND object_count >= 0 AND object_bytes >= 0 AND
             snapshot_row_count >= 0 AND entity_version_row_count >= 0 AND
             attempt_count > 0
             """
           )

    create unique_index(
             :project_snapshot_reset_receipts,
             [:workspace_id, :plan_id],
             name: :project_snapshot_reset_receipts_workspace_plan_idx
           )

    create index(:project_snapshot_reset_receipts, [:workspace_id, :id],
             name: :project_snapshot_reset_receipts_workspace_revision_idx
           )

    create table(:project_snapshot_provider_reset_receipts, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :plan_id, :uuid, null: false
      add :environment, :string, size: 128, null: false
      add :inventory_digest, :string, size: 64, null: false
      add :storage_namespace_fingerprint, :string, size: 64, null: false
      add :authorization_digest, :string, size: 64, null: false
      add :workspace_receipt_ids, {:array, :bigint}, null: false
      add :object_count, :bigint, null: false
      add :object_bytes, :bigint, null: false
      add :scanned_object_count, :bigint, null: false
      add :max_scanned_objects, :bigint, null: false
      add :attempt_count, :bigint, null: false
      add :completed_at, :utc_datetime, null: false

      add :inserted_at, :utc_datetime,
        null: false,
        default: fragment("date_trunc('second', timezone('UTC', now()))::timestamp")
    end

    create constraint(
             :project_snapshot_provider_reset_receipts,
             :project_snapshot_provider_reset_receipts_workspace_receipt_ids,
             check: "storyarn_valid_sorted_positive_bigints(workspace_receipt_ids)"
           )

    create constraint(
             :project_snapshot_provider_reset_receipts,
             :project_snapshot_provider_reset_receipts_environment,
             check: "environment ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'"
           )

    create constraint(
             :project_snapshot_provider_reset_receipts,
             :project_snapshot_provider_reset_receipts_digests,
             check: """
             inventory_digest ~ '^[0-9a-f]{64}$' AND
             storage_namespace_fingerprint ~ '^[0-9a-f]{64}$' AND
             authorization_digest ~ '^[0-9a-f]{64}$'
             """
           )

    create constraint(
             :project_snapshot_provider_reset_receipts,
             :project_snapshot_provider_reset_receipts_counts,
             check: """
             object_count >= 0 AND object_bytes >= 0 AND
             scanned_object_count >= object_count AND
             max_scanned_objects > 0 AND scanned_object_count <= max_scanned_objects AND
             attempt_count > 0
             """
           )

    create unique_index(
             :project_snapshot_provider_reset_receipts,
             [:plan_id],
             name: :project_snapshot_provider_reset_receipts_plan_idx
           )

    execute("""
    CREATE FUNCTION storyarn_reject_snapshot_reset_receipt_mutation()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'snapshot reset receipts are immutable'
        USING ERRCODE = 'check_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER storyarn_guard_project_snapshot_reset_receipt
    BEFORE UPDATE OR DELETE ON project_snapshot_reset_receipts
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_reject_snapshot_reset_receipt_mutation();
    """)

    execute("""
    CREATE TRIGGER storyarn_guard_project_snapshot_provider_reset_receipt
    BEFORE UPDATE OR DELETE ON project_snapshot_provider_reset_receipts
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_reject_snapshot_reset_receipt_mutation();
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS storyarn_guard_project_snapshot_provider_reset_receipt
      ON project_snapshot_provider_reset_receipts;
    """)

    execute("""
    DROP TRIGGER IF EXISTS storyarn_guard_project_snapshot_reset_receipt
      ON project_snapshot_reset_receipts;
    """)

    drop table(:project_snapshot_provider_reset_receipts)
    drop table(:project_snapshot_reset_receipts)

    execute("DROP FUNCTION IF EXISTS storyarn_reject_snapshot_reset_receipt_mutation()")
    execute("DROP FUNCTION IF EXISTS storyarn_valid_sorted_positive_bigints(bigint[])")
  end
end
