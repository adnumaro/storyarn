defmodule Storyarn.Repo.Migrations.AddSnapshotStorageAccounting do
  use Ecto.Migration

  def change do
    # Reset policy: the canonical accounting contract intentionally has no
    # compatibility path for project snapshots created before this rollout.
    # Clear any restoration lock that references those rows before deleting
    # them, otherwise the restrict FK on projects blocks the reset. This runs
    # before the new constraints and is deliberately repeatable after a
    # rollback/reapply cycle.
    execute(
      """
      UPDATE projects
      SET restoration_in_progress = FALSE,
          restoration_started_by_id = NULL,
          restoration_started_at = NULL,
          restoration_token = NULL,
          restoration_claimed_by_job_id = NULL,
          restoration_snapshot_id = NULL
      WHERE restoration_snapshot_id IS NOT NULL
      """,
      "SELECT 1"
    )

    execute("DELETE FROM project_snapshots", "SELECT 1")

    # The rollout contract resets persisted version-control data as well as
    # project-level snapshots. Current-version foreign keys use ON DELETE SET
    # NULL, so no entity can continue pointing at a pre-rollout archive.
    execute("DELETE FROM entity_versions", "SELECT 1")

    # The reset also removes every persisted job for the retired synchronous
    # snapshot implementation. Otherwise Oban could execute a module that no
    # longer exists after deployment, including a job already in a terminal
    # state that an operator might retry later.
    execute(
      """
      DELETE FROM oban_jobs
      WHERE worker IN (
        'Storyarn.Workers.DailySnapshotWorker',
        'Storyarn.Workers.SnapshotRetentionWorker',
        'Storyarn.Workers.RestoreProjectWorker',
        'Storyarn.Workers.RecoverProjectWorker'
      )
      """,
      "SELECT 1"
    )

    execute(
      "ALTER TABLE projects DROP CONSTRAINT projects_restoration_lock_consistency",
      """
      ALTER TABLE projects
      ADD CONSTRAINT projects_restoration_lock_consistency
      CHECK (
        (
          restoration_in_progress = TRUE
          AND restoration_started_by_id IS NOT NULL
          AND restoration_started_at IS NOT NULL
          AND restoration_token IS NOT NULL
          AND (
            restoration_claimed_by_job_id IS NULL
            OR restoration_claimed_by_job_id > 0
          )
          AND restoration_snapshot_id IS NOT NULL
        )
        OR
        (
          restoration_in_progress = FALSE
          AND restoration_started_by_id IS NULL
          AND restoration_started_at IS NULL
          AND restoration_token IS NULL
          AND restoration_claimed_by_job_id IS NULL
          AND restoration_snapshot_id IS NULL
        )
      )
      """
    )

    drop index(:projects, [:restoration_snapshot_id])

    alter table(:projects) do
      remove :auto_snapshots_enabled, :boolean, default: true, null: false
      remove :restoration_in_progress, :boolean, default: false, null: false
      remove :restoration_started_by_id, references(:users, on_delete: :nilify_all)
      remove :restoration_started_at, :utc_datetime
      remove :restoration_token, :uuid
      remove :restoration_claimed_by_job_id, :bigint
      remove :restoration_snapshot_id, references(:project_snapshots, on_delete: :restrict)
    end

    rename table(:project_snapshots), :storage_key, to: :project_storage_key
    rename table(:project_snapshots), :snapshot_size_bytes, to: :project_size_bytes
    rename table(:project_snapshots), :checksum, to: :project_checksum

    execute(
      """
      ALTER TABLE project_snapshots
      RENAME CONSTRAINT project_snapshots_checksum_format
      TO project_snapshots_project_checksum_format
      """,
      """
      ALTER TABLE project_snapshots
      RENAME CONSTRAINT project_snapshots_project_checksum_format
      TO project_snapshots_checksum_format
      """
    )

    alter table(:project_snapshots) do
      add :mode, :string
      add :lifecycle_state, :string
      add :integrity_state, :string
      add :accounted_size_bytes, :bigint
      add :asset_blob_size_bytes, :bigint
      add :accounting_version, :integer
      add :accounting_generation, :bigint
      add :accounting_measured_at, :utc_datetime
    end

    create constraint(:project_snapshots, :project_snapshots_mode,
             check: "mode IN ('full', 'linked')"
           )

    create constraint(:project_snapshots, :project_snapshots_lifecycle_state,
             check: """
             lifecycle_state IN
               ('pending', 'building', 'verifying', 'ready', 'failed', 'cancelled', 'deleting')
             """
           )

    create constraint(:project_snapshots, :project_snapshots_integrity_state,
             check: """
             integrity_state IN
               ('unknown', 'verified', 'missing', 'corrupt', 'at_risk', 'incomplete')
             """
           )

    create constraint(:project_snapshots, :project_snapshots_mode_integrity,
             check: """
             (mode = 'full' AND integrity_state IN
               ('unknown', 'verified', 'missing', 'corrupt', 'incomplete')) OR
             (mode = 'linked' AND integrity_state IN
               ('unknown', 'verified', 'at_risk', 'incomplete'))
             """
           )

    create constraint(:project_snapshots, :project_snapshots_accounting_identity,
             check: """
             format_version IS NOT NULL AND format_version = 1 AND
             mode IS NOT NULL AND lifecycle_state IS NOT NULL AND integrity_state IS NOT NULL
             """
           )

    create constraint(:project_snapshots, :project_snapshots_full_asset_blobs,
             check:
               "mode <> 'full' OR asset_count IS NULL OR asset_count = 0 OR " <>
                 "(blob_count IS NOT NULL AND blob_count > 0)"
           )

    create constraint(:project_snapshots, :project_snapshots_object_target,
             check: """
             object_prefix IS NOT NULL AND
             object_prefix ~
               ('^projects/' || project_id ||
                '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
             project_storage_key IS NOT NULL AND
             project_storage_key = object_prefix || '/project.json' AND
             manifest_storage_key IS NOT NULL AND
             manifest_storage_key = object_prefix || '/manifest.json'
             """
           )

    create constraint(:project_snapshots, :project_snapshots_accounting_measurement,
             check: """
             (accounted_size_bytes IS NULL AND asset_blob_size_bytes IS NULL AND
              accounting_version IS NULL AND accounting_generation IS NULL AND
              accounting_measured_at IS NULL) OR
             (lifecycle_state IN ('ready', 'deleting') AND
              accounted_size_bytes IS NOT NULL AND accounted_size_bytes > 0 AND
              asset_blob_size_bytes IS NOT NULL AND asset_blob_size_bytes >= 0 AND
              accounting_version IS NOT NULL AND accounting_version = 1 AND
              accounting_generation IS NOT NULL AND accounting_generation > 0 AND
              accounting_measured_at IS NOT NULL)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_ready_accounting,
             check: """
             lifecycle_state NOT IN ('ready', 'deleting') OR
             (mode IS NOT NULL AND integrity_state IS NOT NULL AND
              accounted_size_bytes IS NOT NULL AND asset_blob_size_bytes IS NOT NULL AND
              accounting_version IS NOT NULL AND accounting_generation IS NOT NULL AND
              accounting_measured_at IS NOT NULL)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_ready_object_set,
             check: """
             lifecycle_state NOT IN ('ready', 'deleting') OR
             (format_version = 1 AND
              object_prefix IS NOT NULL AND btrim(object_prefix) <> '' AND
              object_prefix ~
                ('^projects/' || project_id ||
                 '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
              project_storage_key IS NOT NULL AND
              project_storage_key = object_prefix || '/project.json' AND
              project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
              project_checksum IS NOT NULL AND project_checksum ~ '^[0-9a-f]{64}$' AND
              manifest_storage_key IS NOT NULL AND
              manifest_storage_key = object_prefix || '/manifest.json' AND
              manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
              manifest_checksum IS NOT NULL AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
              total_size_bytes IS NOT NULL AND total_size_bytes > 0 AND object_count IS NOT NULL AND
              asset_count IS NOT NULL AND blob_count IS NOT NULL)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_full_ready_accounting,
             check: """
             mode <> 'full' OR lifecycle_state NOT IN ('ready', 'deleting') OR
             (total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
              accounted_size_bytes = total_size_bytes AND
              total_size_bytes = project_size_bytes + manifest_size_bytes + asset_blob_size_bytes)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_linked_asset_bytes,
             check: """
             mode <> 'linked' OR asset_blob_size_bytes IS NULL OR
             asset_blob_size_bytes = 0
             """
           )

    create constraint(:project_snapshots, :project_snapshots_linked_ready_accounting,
             check: """
             mode <> 'linked' OR lifecycle_state NOT IN ('ready', 'deleting') OR
             (total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
              accounted_size_bytes = total_size_bytes AND
              total_size_bytes = project_size_bytes + manifest_size_bytes AND
              blob_count = 0 AND object_count = 2)
             """
           )

    create table(:storage_cleanup_ownership_receipts, primary_key: false) do
      add :cleanup_request_id, :bigint, primary_key: true
      add :storage_keys, {:array, :text}, null: false
      add :recorded_at, :utc_datetime, null: false
    end

    create constraint(
             :storage_cleanup_ownership_receipts,
             :storage_cleanup_ownership_receipts_keys_not_empty,
             check: "cardinality(storage_keys) > 0"
           )

    create table(:storage_cleanup_ownership_namespaces, primary_key: false) do
      add :cleanup_request_id,
          references(:storage_cleanup_ownership_receipts,
            column: :cleanup_request_id,
            type: :bigint,
            on_delete: :restrict
          ),
          primary_key: true

      add :object_prefix, :text, primary_key: true
    end

    create index(:storage_cleanup_ownership_namespaces, [:object_prefix],
             name: :storage_cleanup_ownership_namespaces_prefix_idx
           )

    create constraint(
             :storage_cleanup_ownership_namespaces,
             :storage_cleanup_ownership_namespaces_canonical_prefix,
             check: """
             object_prefix ~
               '^projects/[1-9][0-9]*/snapshots/object-sets/v1/(staging|ready)/[A-Za-z0-9_-]{16}$' OR
             object_prefix ~
               '^projects/[1-9][0-9]*/storage-reservations/v1/(snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             """
           )

    create table(:snapshot_object_publication_claims, primary_key: false) do
      add :object_prefix, :string, size: 500, primary_key: true
      add :claim_token, :uuid, null: false
      add :inventory_digest, :string, size: 64, null: false
      add :storage_reservation_id_snapshot, :bigint, null: false
      add :storage_reservation_lease_token, :uuid, null: false
      add :status, :string, null: false
      add :lease_expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:snapshot_object_publication_claims, [:claim_token])

    create unique_index(:snapshot_object_publication_claims, [:storage_reservation_id_snapshot],
             where: "storage_reservation_id_snapshot IS NOT NULL",
             name: :snapshot_object_publication_claims_reservation_idx
           )

    create index(:snapshot_object_publication_claims, [:status, :updated_at])
    create index(:snapshot_object_publication_claims, [:status, :lease_expires_at])

    create constraint(
             :snapshot_object_publication_claims,
             :snapshot_object_publication_claims_identity,
             check: """
             object_prefix ~
               '^projects/[1-9][0-9]*/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$' AND
             inventory_digest ~ '^[0-9a-f]{64}$' AND
             status IN ('staging', 'staged', 'publishing', 'published', 'poisoned') AND
             storage_reservation_id_snapshot > 0 AND
             ((status IN ('staging', 'publishing') AND lease_expires_at IS NOT NULL) OR
              (status IN ('staged', 'published', 'poisoned') AND lease_expires_at IS NULL))
             """
           )

    execute(
      """
      CREATE FUNCTION storyarn_guard_snapshot_publication_claim_update()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.object_prefix IS DISTINCT FROM OLD.object_prefix OR
           NEW.claim_token IS DISTINCT FROM OLD.claim_token OR
           NEW.inventory_digest IS DISTINCT FROM OLD.inventory_digest OR
           NEW.storage_reservation_id_snapshot IS DISTINCT FROM
             OLD.storage_reservation_id_snapshot OR
           NEW.storage_reservation_lease_token IS DISTINCT FROM
             OLD.storage_reservation_lease_token OR
           NEW.inserted_at IS DISTINCT FROM OLD.inserted_at THEN
          RAISE EXCEPTION 'snapshot publication claim identity is immutable'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        IF NOT (
          NEW.status = OLD.status OR
          (OLD.status = 'staging' AND NEW.status IN ('staged', 'poisoned')) OR
          (OLD.status = 'staged' AND NEW.status IN ('publishing', 'poisoned')) OR
          (OLD.status = 'publishing' AND NEW.status IN ('published', 'poisoned'))
        ) THEN
          RAISE EXCEPTION 'snapshot publication claim state cannot move backwards'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        RETURN NEW;
      END;
      $$
      """,
      "DROP FUNCTION IF EXISTS storyarn_guard_snapshot_publication_claim_update() CASCADE"
    )

    execute(
      """
      CREATE TRIGGER snapshot_object_publication_claims_update_guard
      BEFORE UPDATE ON snapshot_object_publication_claims
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_guard_snapshot_publication_claim_update()
      """,
      "DROP TRIGGER IF EXISTS snapshot_object_publication_claims_update_guard ON snapshot_object_publication_claims"
    )

    execute(
      """
      CREATE FUNCTION storyarn_capture_storage_cleanup_ownership_receipt()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM unnest(NEW.storage_keys) AS storage_key
          WHERE storage_key ~
            '^projects/[1-9][0-9]*/snapshots/object-sets/v1/(staging|ready)/[A-Za-z0-9_-]{16}/' OR
            storage_key ~
            '^projects/[1-9][0-9]*/storage-reservations/v1/(snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
        ) THEN
          INSERT INTO storage_cleanup_ownership_receipts
            (cleanup_request_id, storage_keys, recorded_at)
          VALUES
            (NEW.id, NEW.storage_keys, NEW.inserted_at);

          INSERT INTO storage_cleanup_ownership_namespaces
            (cleanup_request_id, object_prefix)
          SELECT NEW.id, object_prefix
          FROM (
            SELECT substring(
              storage_key FROM
              '^(projects/[1-9][0-9]*/snapshots/object-sets/v1/(?:staging|ready)/[A-Za-z0-9_-]{16})/'
            ) AS object_prefix
            FROM unnest(NEW.storage_keys) AS storage_key
            UNION
            SELECT substring(
              storage_key FROM
              '^(projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'
            ) AS object_prefix
            FROM unnest(NEW.storage_keys) AS storage_key
          ) AS owned_namespaces
          WHERE object_prefix IS NOT NULL
          ON CONFLICT (cleanup_request_id, object_prefix) DO NOTHING;
        END IF;

        RETURN NEW;
      END;
      $$
      """,
      "DROP FUNCTION IF EXISTS storyarn_capture_storage_cleanup_ownership_receipt()"
    )

    execute(
      """
      CREATE TRIGGER storage_cleanup_requests_capture_ownership_receipt
      AFTER INSERT ON storage_cleanup_requests
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_capture_storage_cleanup_ownership_receipt()
      """,
      "DROP TRIGGER IF EXISTS storage_cleanup_requests_capture_ownership_receipt ON storage_cleanup_requests"
    )

    execute(
      """
      INSERT INTO storage_cleanup_ownership_receipts
        (cleanup_request_id, storage_keys, recorded_at)
      SELECT id, storage_keys, inserted_at
      FROM storage_cleanup_requests
      WHERE EXISTS (
        SELECT 1
        FROM unnest(storage_cleanup_requests.storage_keys) AS storage_key
        WHERE storage_key ~
          '^projects/[1-9][0-9]*/snapshots/object-sets/v1/(staging|ready)/[A-Za-z0-9_-]{16}/' OR
          storage_key ~
          '^projects/[1-9][0-9]*/storage-reservations/v1/(snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
      )
      ON CONFLICT (cleanup_request_id) DO NOTHING
      """,
      "SELECT 1"
    )

    execute(
      """
      INSERT INTO storage_cleanup_ownership_namespaces
        (cleanup_request_id, object_prefix)
      SELECT cleanup_request_id, object_prefix
      FROM (
        SELECT request.id AS cleanup_request_id,
               substring(
                 storage_key FROM
                 '^(projects/[1-9][0-9]*/snapshots/object-sets/v1/(?:staging|ready)/[A-Za-z0-9_-]{16})/'
               ) AS object_prefix
        FROM storage_cleanup_requests AS request,
             unnest(request.storage_keys) AS storage_key
        UNION
        SELECT request.id AS cleanup_request_id,
               substring(
                 storage_key FROM
                 '^(projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'
               ) AS object_prefix
        FROM storage_cleanup_requests AS request,
             unnest(request.storage_keys) AS storage_key
      ) AS owned_namespaces
      WHERE object_prefix IS NOT NULL
      ON CONFLICT (cleanup_request_id, object_prefix) DO NOTHING
      """,
      "SELECT 1"
    )

    execute(
      """
      CREATE FUNCTION storyarn_reject_storage_cleanup_ownership_receipt_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'storage cleanup ownership receipts are immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END;
      $$
      """,
      "DROP FUNCTION IF EXISTS storyarn_reject_storage_cleanup_ownership_receipt_mutation()"
    )

    execute(
      """
      CREATE TRIGGER storage_cleanup_ownership_receipts_immutable
      BEFORE UPDATE OR DELETE ON storage_cleanup_ownership_receipts
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_reject_storage_cleanup_ownership_receipt_mutation()
      """,
      "DROP TRIGGER IF EXISTS storage_cleanup_ownership_receipts_immutable ON storage_cleanup_ownership_receipts"
    )

    execute(
      """
      CREATE TRIGGER storage_cleanup_ownership_namespaces_immutable
      BEFORE UPDATE OR DELETE ON storage_cleanup_ownership_namespaces
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_reject_storage_cleanup_ownership_receipt_mutation()
      """,
      "DROP TRIGGER IF EXISTS storage_cleanup_ownership_namespaces_immutable ON storage_cleanup_ownership_namespaces"
    )

    create table(:workspace_storage_reservations) do
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :project_snapshot_id, references(:project_snapshots, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint, null: false
      add :project_id_snapshot, :bigint, null: false
      add :project_snapshot_id_snapshot, :bigint, null: false
      add :idempotency_key, :string, null: false
      add :kind, :string, null: false
      add :status, :string, null: false
      add :storage_namespace, :string, size: 500, null: false
      add :cleanup_object_prefix, :string, size: 500, null: false
      add :source_asset_count, :bigint
      add :reserved_bytes, :bigint, null: false
      add :actual_bytes, :bigint
      add :lease_token, :uuid, null: false
      add :generation, :integer, null: false
      add :expires_at, :utc_datetime, null: false
      add :storage_started_at, :utc_datetime
      add :cleanup_inventory_digest, :string, size: 64
      add :cleanup_inventory_count, :bigint
      add :settled_at, :utc_datetime
      add :release_reason, :string
      add :cleanup_status, :string
      add :cleanup_reference, :string, size: 500
      add :accounting_version, :integer, null: false
      add :accounting_measured_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :workspace_storage_reservations,
             [:workspace_id_snapshot, :idempotency_key],
             name: :workspace_storage_reservations_workspace_idempotency_idx
           )

    create unique_index(:workspace_storage_reservations, [:lease_token])
    create unique_index(:workspace_storage_reservations, [:storage_namespace])

    create unique_index(:workspace_storage_reservations, [:cleanup_object_prefix],
             where: "kind IN ('snapshot_build', 'linked_to_full_conversion')",
             name: :workspace_storage_reservations_ready_prefix_idx
           )

    create unique_index(
             :workspace_storage_reservations,
             [:project_snapshot_id_snapshot],
             where:
               "status = 'active' AND kind IN ('snapshot_build', 'linked_to_full_conversion')",
             name: :workspace_storage_reservations_active_snapshot_operation_idx
           )

    create index(:workspace_storage_reservations, [:workspace_id_snapshot, :status],
             name: :workspace_storage_reservations_workspace_status_idx
           )

    create index(:workspace_storage_reservations, [:project_id_snapshot, :status])
    create index(:workspace_storage_reservations, [:project_snapshot_id])
    create index(:workspace_storage_reservations, [:project_snapshot_id_snapshot])

    create index(:workspace_storage_reservations, [:expires_at],
             where: "status = 'active'",
             name: :workspace_storage_reservations_active_expiry_idx
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_kind,
             check: """
             kind IN
               ('snapshot_build', 'linked_to_full_conversion', 'restore_staging', 'snapshot_export')
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_status,
             check: "status IN ('active', 'committed', 'released')"
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_positive_values,
             check: """
             ((kind = 'linked_to_full_conversion' AND reserved_bytes >= 0) OR
              (kind <> 'linked_to_full_conversion' AND reserved_bytes > 0)) AND
             (actual_bytes IS NULL OR
              (((kind = 'linked_to_full_conversion' AND actual_bytes >= 0) OR
                (kind <> 'linked_to_full_conversion' AND actual_bytes > 0)) AND
               actual_bytes <= reserved_bytes)) AND
             generation > 0 AND accounting_version = 1 AND
             (status <> 'active' OR expires_at > accounting_measured_at)
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_source_inventory,
             check: """
             (kind = 'linked_to_full_conversion' AND source_asset_count IS NOT NULL AND
              source_asset_count >= 0) OR
             (kind <> 'linked_to_full_conversion' AND source_asset_count IS NULL)
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_identity,
             check: """
             (workspace_id IS NULL OR workspace_id = workspace_id_snapshot) AND
             (project_id IS NULL OR project_id = project_id_snapshot) AND
             (project_snapshot_id IS NULL OR
              project_snapshot_id = project_snapshot_id_snapshot)
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_cleanup_inventory_commitment,
             check: """
             (storage_started_at IS NULL AND cleanup_inventory_digest IS NULL AND
              cleanup_inventory_count IS NULL) OR
             (storage_started_at IS NOT NULL AND
              cleanup_inventory_digest IS NOT NULL AND
              cleanup_inventory_digest ~ '^[0-9a-f]{64}$' AND
              cleanup_inventory_count IS NOT NULL AND cleanup_inventory_count > 0)
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_namespace,
             check: """
             storage_namespace ~
               '^projects/[1-9][0-9]*/storage-reservations/v1/(snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND
             storage_namespace =
               'projects/' || project_id_snapshot || '/storage-reservations/v1/' ||
               replace(kind, '_', '-') || '/' || lease_token::text
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_cleanup_object_prefix,
             check: """
             (kind IN ('snapshot_build', 'linked_to_full_conversion') AND
              cleanup_object_prefix ~
                '^projects/[1-9][0-9]*/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$' AND
              cleanup_object_prefix LIKE
                'projects/' || project_id_snapshot || '/snapshots/object-sets/v1/ready/%') OR
             (kind IN ('restore_staging', 'snapshot_export') AND
              cleanup_object_prefix = storage_namespace)
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_terminal_fields,
             check: """
             (status = 'active' AND actual_bytes IS NULL AND settled_at IS NULL AND
              release_reason IS NULL AND cleanup_status IS NULL AND cleanup_reference IS NULL) OR
             (status = 'committed' AND actual_bytes IS NOT NULL AND settled_at IS NOT NULL AND
              storage_started_at IS NOT NULL AND release_reason IS NULL AND
              cleanup_status IS NULL AND cleanup_reference IS NULL) OR
             (status = 'released' AND actual_bytes IS NULL AND settled_at IS NOT NULL AND
              release_reason IS NOT NULL AND btrim(release_reason) <> '' AND
              cleanup_status IS NOT NULL AND cleanup_status IN ('not_required', 'owned'))
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_cleanup_reference,
             check: """
             cleanup_status IS NULL OR
             (cleanup_status = 'not_required' AND storage_started_at IS NULL AND
              cleanup_reference IS NOT NULL AND
              cleanup_reference = 'storage_not_started:' || storage_namespace) OR
             (cleanup_status = 'owned' AND storage_started_at IS NOT NULL AND
              cleanup_reference IS NOT NULL AND
              cleanup_reference ~ '^storage_cleanup_request:[1-9][0-9]*$')
             """
           )

    execute(
      """
      ALTER TABLE snapshot_object_publication_claims
      ADD CONSTRAINT snapshot_object_publication_claims_reservation_fkey
      FOREIGN KEY (storage_reservation_id_snapshot)
      REFERENCES workspace_storage_reservations(id)
      ON DELETE RESTRICT
      """,
      """
      ALTER TABLE snapshot_object_publication_claims
      DROP CONSTRAINT IF EXISTS snapshot_object_publication_claims_reservation_fkey
      """
    )
  end
end
