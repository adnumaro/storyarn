defmodule Storyarn.Repo.Migrations.MakeProjectSnapshotsV2Only do
  @moduledoc """
  Removes the retired v1/linked snapshot contract after the archive rollout.

  Physical snapshot ownership cannot be deleted transactionally with Postgres,
  so the migration fails closed while any v1/linked ownership row or live
  operation/cleanup request remains. Operators must let live jobs settle and
  purge retired ownership with the old binary before retrying. Terminal
  immutable cleanup receipts and namespaces are preserved as audit evidence;
  the replacement trigger function never creates new v1 evidence. The two
  retired physical columns remain nullable and unused for one rolling-deploy
  boundary so the pre-cutover binary can still read the tables while this
  migration runs.
  """

  use Ecto.Migration

  @snapshot_constraints [
    :project_snapshots_object_format_version,
    :project_snapshots_archive_format,
    :project_snapshots_object_counts,
    :project_snapshots_mode,
    :project_snapshots_mode_integrity,
    :project_snapshots_accounting_identity,
    :project_snapshots_object_target,
    :project_snapshots_ready_object_set,
    :project_snapshots_full_ready_accounting,
    :project_snapshots_linked_asset_bytes,
    :project_snapshots_linked_ready_accounting
  ]

  @reservation_constraints [
    :workspace_storage_reservations_kind,
    :workspace_storage_reservations_positive_values,
    :workspace_storage_reservations_source_inventory,
    :workspace_storage_reservations_namespace,
    :workspace_storage_reservations_cleanup_object_prefix
  ]

  def up do
    lock_snapshot_contract_tables()
    assert_no_live_legacy_ownership!()

    replace_project_snapshot_contract()
    replace_publication_claim_contract()
    replace_storage_reservation_contract()
    replace_cleanup_intent_contract()
    replace_cleanup_ownership_capture()
  end

  def down do
    raise Ecto.MigrationError,
          "MakeProjectSnapshotsV2Only is irreversible: v1/linked columns and constraints cannot be reconstructed"
  end

  defp lock_snapshot_contract_tables do
    execute("""
    LOCK TABLE
      project_snapshots,
      snapshot_object_publication_claims,
      workspace_storage_reservations,
      snapshot_cleanup_intents,
      storage_cleanup_requests,
      storage_cleanup_ownership_namespaces,
      oban_jobs
    IN ACCESS EXCLUSIVE MODE
    """)
  end

  defp assert_no_live_legacy_ownership! do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM project_snapshots
        WHERE format_version IS DISTINCT FROM 2 OR mode IS DISTINCT FROM 'full'
      ) OR EXISTS (
        SELECT 1
        FROM snapshot_object_publication_claims
        WHERE object_prefix ~ '/snapshots/object-sets/v1/'
      ) OR EXISTS (
        SELECT 1
        FROM workspace_storage_reservations
        WHERE kind = 'linked_to_full_conversion'
           OR cleanup_object_prefix ~ '/snapshots/object-sets/v1/'
      ) OR EXISTS (
        SELECT 1
        FROM snapshot_cleanup_intents
        WHERE mode IS DISTINCT FROM 'full'
           OR ready_prefix ~ '/snapshots/object-sets/v1/'
           OR staging_prefix ~ '/snapshots/object-sets/v1/'
      ) OR EXISTS (
        SELECT 1
        FROM storage_cleanup_requests AS cleanup_request,
             unnest(cleanup_request.storage_keys) AS storage_key
        WHERE storage_key ~ '/snapshots/object-sets/v1/'
           OR storage_key ~ '/storage-reservations/v1/linked-to-full-conversion/'
      ) OR EXISTS (
        SELECT 1
        FROM oban_jobs
        WHERE worker = 'Storyarn.Workers.BuildProjectSnapshotWorker'
          AND state IN ('available', 'scheduled', 'executing', 'retryable')
      ) OR EXISTS (
        SELECT 1
        FROM oban_jobs AS cleanup_job
        CROSS JOIN LATERAL jsonb_array_elements_text(
          CASE
            WHEN jsonb_typeof(cleanup_job.args -> 'storage_keys') = 'array'
              THEN cleanup_job.args -> 'storage_keys'
            ELSE '[]'::jsonb
          END
        ) AS cleanup_key(storage_key)
        WHERE cleanup_job.state IN ('available', 'scheduled', 'executing', 'retryable')
          AND (
            cleanup_key.storage_key ~ '/snapshots/object-sets/v1/' OR
            cleanup_key.storage_key ~ '/storage-reservations/v1/linked-to-full-conversion/'
          )
      ) THEN
        RAISE EXCEPTION
          'v2-only snapshot migration requires retired ownership to be purged and every snapshot build job to be quiescent under the pre-cutover binary'
          USING ERRCODE = 'object_not_in_prerequisite_state';
      END IF;
    END;
    $$
    """)
  end

  defp replace_project_snapshot_contract do
    Enum.each(@snapshot_constraints, &drop(constraint(:project_snapshots, &1)))

    create constraint(:project_snapshots, :project_snapshots_object_format_version,
             check: "format_version = 2"
           )

    create constraint(:project_snapshots, :project_snapshots_archive_format,
             check: """
             format_version = 2 AND mode = 'full' AND
             archive_storage_key IS NOT NULL AND
             ((lifecycle_state IN ('pending', 'failed', 'cancelled', 'deleting') AND
               capture_digest IS NULL AND project_size_bytes IS NULL AND
               project_checksum IS NULL AND captured_at IS NULL AND
               archive_size_bytes IS NULL AND archive_checksum IS NULL AND
               manifest_size_bytes IS NULL AND manifest_checksum IS NULL AND
               total_size_bytes IS NULL AND object_count IS NULL AND
               asset_count IS NULL AND blob_count IS NULL) OR
              (project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
               project_checksum IS NOT NULL AND
               project_checksum ~ '^[0-9a-f]{64}$' AND
               capture_digest IS NOT NULL AND capture_digest ~ '^[0-9a-f]{64}$' AND
               captured_at IS NOT NULL AND archive_size_bytes IS NOT NULL AND
               archive_size_bytes > 0 AND
               (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$') AND
               manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
               manifest_checksum IS NOT NULL AND
               manifest_checksum ~ '^[0-9a-f]{64}$' AND
               total_size_bytes = archive_size_bytes + manifest_size_bytes AND
               object_count = 2 AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
               progress_total_bytes = total_size_bytes))
             """
           )

    create constraint(:project_snapshots, :project_snapshots_object_counts,
             check: """
             (object_count IS NULL AND asset_count IS NULL AND blob_count IS NULL) OR
             (object_count = 2 AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
              blob_count >= 0 AND asset_count >= blob_count)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_mode, check: "mode = 'full'")

    create constraint(:project_snapshots, :project_snapshots_mode_integrity,
             check: """
             mode = 'full' AND
             integrity_state IN ('unknown', 'verified', 'missing', 'corrupt', 'incomplete')
             """
           )

    create constraint(:project_snapshots, :project_snapshots_accounting_identity,
             check: """
             format_version = 2 AND mode = 'full' AND
             lifecycle_state IS NOT NULL AND integrity_state IS NOT NULL
             """
           )

    create constraint(:project_snapshots, :project_snapshots_object_target,
             check: """
             format_version = 2 AND mode = 'full' AND object_prefix IS NOT NULL AND
             object_prefix ~ ('^projects/' || project_id ||
               '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
             archive_storage_key = object_prefix || '/snapshot.zip' AND
             manifest_storage_key IS NOT NULL AND
             manifest_storage_key = object_prefix || '/manifest.json'
             """
           )

    create constraint(:project_snapshots, :project_snapshots_ready_object_set,
             check: """
             lifecycle_state <> 'ready' OR
             (format_version = 2 AND mode = 'full' AND object_prefix IS NOT NULL AND
              btrim(object_prefix) <> '' AND
              object_prefix ~ ('^projects/' || project_id ||
                '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
              archive_storage_key = object_prefix || '/snapshot.zip' AND
              archive_size_bytes IS NOT NULL AND archive_size_bytes > 0 AND
              archive_checksum IS NOT NULL AND archive_checksum ~ '^[0-9a-f]{64}$' AND
              project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
              project_checksum IS NOT NULL AND project_checksum ~ '^[0-9a-f]{64}$' AND
              manifest_storage_key IS NOT NULL AND
              manifest_storage_key = object_prefix || '/manifest.json' AND
              manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
              manifest_checksum IS NOT NULL AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
              total_size_bytes IS NOT NULL AND total_size_bytes > 0 AND
              object_count = 2 AND asset_count IS NOT NULL AND blob_count IS NOT NULL)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_full_ready_accounting,
             check: """
             lifecycle_state <> 'ready' OR
             (total_size_bytes IS NOT NULL AND archive_size_bytes IS NOT NULL AND
              manifest_size_bytes IS NOT NULL AND accounted_size_bytes = total_size_bytes AND
              total_size_bytes = archive_size_bytes + manifest_size_bytes)
             """
           )

    alter table(:project_snapshots) do
      modify :format_version, :integer, null: false, default: 2
      modify :mode, :string, null: false, default: "full"
    end

    execute("ALTER TABLE project_snapshots ALTER COLUMN project_storage_key DROP NOT NULL")
  end

  defp replace_publication_claim_contract do
    drop constraint(
           :snapshot_object_publication_claims,
           :snapshot_object_publication_claims_identity
         )

    create constraint(
             :snapshot_object_publication_claims,
             :snapshot_object_publication_claims_identity,
             check: """
             object_prefix ~
               '^projects/[1-9][0-9]*/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$' AND
             inventory_digest ~ '^[0-9a-f]{64}$' AND
             status IN ('staging', 'staged', 'publishing', 'published', 'poisoned') AND
             storage_reservation_id_snapshot > 0 AND
             ((status IN ('staging', 'publishing') AND lease_expires_at IS NOT NULL) OR
              (status IN ('staged', 'published', 'poisoned') AND lease_expires_at IS NULL))
             """
           )
  end

  defp replace_storage_reservation_contract do
    drop index(:workspace_storage_reservations, [:cleanup_object_prefix],
           name: :workspace_storage_reservations_ready_prefix_idx
         )

    drop index(:workspace_storage_reservations, [:project_snapshot_id_snapshot],
           name: :workspace_storage_reservations_active_snapshot_operation_idx
         )

    Enum.each(@reservation_constraints, &drop(constraint(:workspace_storage_reservations, &1)))

    create unique_index(:workspace_storage_reservations, [:cleanup_object_prefix],
             where: "kind = 'snapshot_build'",
             name: :workspace_storage_reservations_ready_prefix_idx
           )

    create unique_index(:workspace_storage_reservations, [:project_snapshot_id_snapshot],
             where: "status = 'active' AND kind = 'snapshot_build'",
             name: :workspace_storage_reservations_active_snapshot_operation_idx
           )

    create constraint(:workspace_storage_reservations, :workspace_storage_reservations_kind,
             check: "kind IN ('snapshot_build', 'restore_staging', 'snapshot_export')"
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_positive_values,
             check: """
             ((kind = 'snapshot_export' AND reserved_bytes >= 0) OR
              (kind <> 'snapshot_export' AND reserved_bytes > 0)) AND
             (actual_bytes IS NULL OR (actual_bytes > 0 AND actual_bytes <= reserved_bytes)) AND
             generation > 0 AND accounting_version = 1 AND
             (status <> 'active' OR expires_at > accounting_measured_at)
             """
           )

    create constraint(:workspace_storage_reservations, :workspace_storage_reservations_namespace,
             check: """
             storage_namespace ~
               '^projects/[1-9][0-9]*/storage-reservations/v1/(snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND
             storage_namespace =
               'projects/' || project_id_snapshot || '/storage-reservations/v1/' ||
               replace(kind, '_', '-') || '/' || lease_token::text
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_cleanup_object_prefix,
             check: """
             (kind = 'snapshot_build' AND cleanup_object_prefix ~
                '^projects/[1-9][0-9]*/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$' AND
              cleanup_object_prefix LIKE
                'projects/' || project_id_snapshot || '/snapshots/archives/v2/ready/%') OR
             (kind IN ('restore_staging', 'snapshot_export') AND
              cleanup_object_prefix = storage_namespace)
             """
           )

    # `source_asset_count` remains nullable and unused for the rolling-read
    # compatibility boundary described in the module documentation.
    execute(
      "ALTER TABLE workspace_storage_reservations ALTER COLUMN source_asset_count DROP NOT NULL"
    )
  end

  defp replace_cleanup_intent_contract do
    drop constraint(:snapshot_cleanup_intents, :snapshot_cleanup_intents_identity)

    create constraint(:snapshot_cleanup_intents, :snapshot_cleanup_intents_identity,
             check: """
             workspace_id_snapshot > 0 AND project_id_snapshot > 0 AND
             project_snapshot_id_snapshot > 0 AND deletion_generation > 0 AND
             mode = 'full' AND
             origin IN ('user', 'daily', 'pre_restore', 'post_restore') AND
             reason IN ('user_delete', 'retention', 'expired_build',
               'project_hard_delete', 'workspace_hard_delete') AND
             authority_kind IN ('user', 'system') AND
             ((authority_kind = 'user' AND authority_actor_id IS NOT NULL AND
               authority_actor_id > 0) OR
              (authority_kind = 'system' AND authority_actor_id IS NULL)) AND
             ready_prefix ~ ('^projects/' || project_id_snapshot ||
               '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
             staging_prefix ~ ('^projects/' || project_id_snapshot ||
               '/snapshots/archives/v2/staging/[A-Za-z0-9_-]{16}$') AND
             inventory_digest ~ '^[0-9a-f]{64}$' AND object_count > 0 AND
             estimated_cleanup_bytes >= 0 AND cardinality(storage_keys) = object_count AND
             status IN ('pending', 'processing', 'retrying', 'completed', 'terminal') AND
             retry_count >= 0 AND processing_generation >= 0 AND
             required_delete_passes = (CASE WHEN reason = 'expired_build' THEN 2 ELSE 1 END) AND
             completed_delete_passes >= 0 AND
             completed_delete_passes <= required_delete_passes AND
             ((required_delete_passes = 1 AND next_delete_pass_at IS NULL) OR
              (required_delete_passes = 2 AND
               ((completed_delete_passes = 0 AND next_delete_pass_at IS NULL) OR
                (completed_delete_passes > 0 AND next_delete_pass_at IS NOT NULL)))) AND
             ((status = 'completed' AND cardinality(remaining_storage_keys) = 0 AND
               completed_at IS NOT NULL) OR
              (status = 'terminal' AND cardinality(remaining_storage_keys) > 0 AND
               terminal_at IS NOT NULL) OR
              (status IN ('pending', 'processing', 'retrying') AND
               cardinality(remaining_storage_keys) > 0 AND completed_at IS NULL AND
               terminal_at IS NULL)) AND
             ((status = 'completed' AND completed_delete_passes = required_delete_passes) OR
              (status <> 'completed' AND completed_delete_passes < required_delete_passes))
             """
           )
  end

  defp replace_cleanup_ownership_capture do
    execute("""
    CREATE OR REPLACE FUNCTION storyarn_capture_storage_cleanup_ownership_receipt()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM unnest(NEW.storage_keys) AS storage_key
        WHERE storage_key ~ '/snapshots/object-sets/v1/'
           OR storage_key ~ '/storage-reservations/v1/linked-to-full-conversion/'
      ) THEN
        RAISE EXCEPTION 'retired v1/linked snapshot cleanup ownership is not accepted'
          USING ERRCODE = 'check_violation';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM unnest(NEW.storage_keys) AS storage_key
        WHERE storage_key ~
          '^projects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16}/' OR
          storage_key ~
          '^projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
      ) THEN
        INSERT INTO storage_cleanup_ownership_receipts
          (cleanup_request_id, storage_keys, recorded_at)
        VALUES (NEW.id, NEW.storage_keys, NEW.inserted_at);

        INSERT INTO storage_cleanup_ownership_namespaces
          (cleanup_request_id, object_prefix)
        SELECT NEW.id, object_prefix
        FROM (
          SELECT substring(storage_key FROM
            '^(projects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16})/'
          ) AS object_prefix
          FROM unnest(NEW.storage_keys) AS storage_key
          UNION
          SELECT substring(storage_key FROM
            '^(projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'
          ) AS object_prefix
          FROM unnest(NEW.storage_keys) AS storage_key
        ) AS owned_namespaces
        WHERE object_prefix IS NOT NULL
        ON CONFLICT (cleanup_request_id, object_prefix) DO NOTHING;
      END IF;

      RETURN NEW;
    END;
    $$
    """)
  end
end
