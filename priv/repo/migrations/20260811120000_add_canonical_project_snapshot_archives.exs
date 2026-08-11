defmodule Storyarn.Repo.Migrations.AddCanonicalProjectSnapshotArchives do
  use Ecto.Migration

  @snapshot_constraints [
    :project_snapshots_object_format_version,
    :project_snapshots_object_counts,
    :project_snapshots_accounting_identity,
    :project_snapshots_object_target,
    :project_snapshots_ready_object_set,
    :project_snapshots_full_ready_accounting
  ]

  def up do
    alter table(:project_snapshots) do
      modify :project_storage_key, :string, null: true, from: {:string, null: false}
      add :archive_storage_key, :string, size: 520
      add :archive_size_bytes, :bigint
      add :archive_checksum, :string, size: 64
    end

    create unique_index(:project_snapshots, [:archive_storage_key],
             where: "archive_storage_key IS NOT NULL"
           )

    drop_snapshot_constraints()

    create constraint(:project_snapshots, :project_snapshots_object_format_version,
             check: "format_version IS NULL OR format_version IN (1, 2)"
           )

    create constraint(:project_snapshots, :project_snapshots_archive_format,
             check: """
             (format_version = 1 AND archive_storage_key IS NULL AND
              archive_size_bytes IS NULL AND archive_checksum IS NULL) OR
             (format_version = 2 AND mode = 'full' AND project_storage_key IS NULL AND
              archive_storage_key IS NOT NULL AND archive_size_bytes IS NOT NULL AND
              archive_size_bytes > 0 AND
              (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$'))
             """
           )

    create constraint(:project_snapshots, :project_snapshots_object_counts,
             check: """
             (object_count IS NULL AND asset_count IS NULL AND blob_count IS NULL) OR
             (object_count IS NOT NULL AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
              blob_count >= 0 AND asset_count >= blob_count AND
              ((format_version = 1 AND object_count = blob_count + 2) OR
               (format_version = 2 AND object_count = 2)))
             """
           )

    create constraint(:project_snapshots, :project_snapshots_accounting_identity,
             check: """
             format_version IS NOT NULL AND format_version IN (1, 2) AND
             mode IS NOT NULL AND lifecycle_state IS NOT NULL AND integrity_state IS NOT NULL
             """
           )

    create constraint(:project_snapshots, :project_snapshots_object_target,
             check: object_target_check([1, 2])
           )

    create constraint(:project_snapshots, :project_snapshots_ready_object_set,
             check: ready_object_set_check([1, 2])
           )

    create constraint(:project_snapshots, :project_snapshots_full_ready_accounting,
             check: full_ready_accounting_check([1, 2])
           )

    replace_claim_constraint([1, 2])
    replace_reservation_constraint([1, 2])
    replace_cleanup_namespace_constraint([1, 2])
    replace_cleanup_intent_constraint([1, 2])
    replace_cleanup_ownership_function([1, 2])
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM project_snapshots WHERE format_version = 2) OR
         EXISTS (SELECT 1 FROM snapshot_object_publication_claims WHERE object_prefix LIKE '%/snapshots/archives/v2/%') OR
         EXISTS (SELECT 1 FROM workspace_storage_reservations WHERE cleanup_object_prefix LIKE '%/snapshots/archives/v2/%') OR
         EXISTS (SELECT 1 FROM snapshot_cleanup_intents WHERE ready_prefix LIKE '%/snapshots/archives/v2/%') OR
         EXISTS (SELECT 1 FROM storage_cleanup_ownership_namespaces WHERE object_prefix LIKE '%/snapshots/archives/v2/%') OR
         EXISTS (
           SELECT 1
           FROM storage_cleanup_requests AS request,
                unnest(request.storage_keys) AS storage_key
           WHERE storage_key LIKE '%/snapshots/archives/v2/%'
         ) THEN
        RAISE EXCEPTION 'cannot remove canonical snapshot archive support while v2 ownership exists'
          USING ERRCODE = 'object_not_in_prerequisite_state';
      END IF;
    END;
    $$
    """)

    replace_cleanup_ownership_function([1])
    replace_cleanup_intent_constraint([1])
    replace_cleanup_namespace_constraint([1])
    replace_reservation_constraint([1])
    replace_claim_constraint([1])

    drop_snapshot_constraints()
    drop constraint(:project_snapshots, :project_snapshots_archive_format)

    create constraint(:project_snapshots, :project_snapshots_object_format_version,
             check: "format_version IS NULL OR format_version = 1"
           )

    create constraint(:project_snapshots, :project_snapshots_object_counts,
             check: """
             (object_count IS NULL AND asset_count IS NULL AND blob_count IS NULL) OR
             (object_count IS NOT NULL AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
              object_count = blob_count + 2 AND blob_count >= 0 AND asset_count >= blob_count)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_accounting_identity,
             check: """
             format_version IS NOT NULL AND format_version = 1 AND
             mode IS NOT NULL AND lifecycle_state IS NOT NULL AND integrity_state IS NOT NULL
             """
           )

    create constraint(:project_snapshots, :project_snapshots_object_target,
             check: object_target_check([1])
           )

    create constraint(:project_snapshots, :project_snapshots_ready_object_set,
             check: ready_object_set_check([1])
           )

    create constraint(:project_snapshots, :project_snapshots_full_ready_accounting,
             check: full_ready_accounting_check([1])
           )

    drop_if_exists unique_index(:project_snapshots, [:archive_storage_key],
                     where: "archive_storage_key IS NOT NULL"
                   )

    alter table(:project_snapshots) do
      remove :archive_checksum
      remove :archive_size_bytes
      remove :archive_storage_key
      modify :project_storage_key, :string, null: false, from: {:string, null: true}
    end
  end

  defp drop_snapshot_constraints do
    Enum.each(@snapshot_constraints, &drop(constraint(:project_snapshots, &1)))
  end

  defp object_target_check([1]) do
    """
    object_prefix IS NOT NULL AND
    object_prefix ~ ('^projects/' || project_id ||
      '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
    project_storage_key IS NOT NULL AND project_storage_key = object_prefix || '/project.json' AND
    manifest_storage_key IS NOT NULL AND manifest_storage_key = object_prefix || '/manifest.json'
    """
  end

  defp object_target_check([1, 2]) do
    """
    (format_version = 1 AND object_prefix IS NOT NULL AND
     object_prefix ~ ('^projects/' || project_id ||
       '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
     project_storage_key IS NOT NULL AND project_storage_key = object_prefix || '/project.json' AND
     archive_storage_key IS NULL AND
     manifest_storage_key IS NOT NULL AND manifest_storage_key = object_prefix || '/manifest.json') OR
    (format_version = 2 AND mode = 'full' AND object_prefix IS NOT NULL AND
     object_prefix ~ ('^projects/' || project_id ||
       '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
     project_storage_key IS NULL AND archive_storage_key = object_prefix || '/snapshot.zip' AND
     manifest_storage_key = object_prefix || '/manifest.json')
    """
  end

  defp ready_object_set_check([1]) do
    """
    lifecycle_state <> 'ready' OR
    (format_version = 1 AND object_prefix IS NOT NULL AND btrim(object_prefix) <> '' AND
     object_prefix ~ ('^projects/' || project_id ||
       '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
     project_storage_key IS NOT NULL AND project_storage_key = object_prefix || '/project.json' AND
     project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
     project_checksum IS NOT NULL AND project_checksum ~ '^[0-9a-f]{64}$' AND
     manifest_storage_key IS NOT NULL AND manifest_storage_key = object_prefix || '/manifest.json' AND
     manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
     manifest_checksum IS NOT NULL AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
     total_size_bytes IS NOT NULL AND total_size_bytes > 0 AND object_count IS NOT NULL AND
     asset_count IS NOT NULL AND blob_count IS NOT NULL)
    """
  end

  defp ready_object_set_check([1, 2]) do
    """
    lifecycle_state <> 'ready' OR
    (format_version = 1 AND object_prefix IS NOT NULL AND btrim(object_prefix) <> '' AND
     object_prefix ~ ('^projects/' || project_id ||
       '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
     project_storage_key IS NOT NULL AND project_storage_key = object_prefix || '/project.json' AND
     archive_storage_key IS NULL AND
     project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
     project_checksum IS NOT NULL AND project_checksum ~ '^[0-9a-f]{64}$' AND
     manifest_storage_key IS NOT NULL AND manifest_storage_key = object_prefix || '/manifest.json' AND
     manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
     manifest_checksum IS NOT NULL AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
     total_size_bytes IS NOT NULL AND total_size_bytes > 0 AND object_count IS NOT NULL AND
     asset_count IS NOT NULL AND blob_count IS NOT NULL) OR
    (format_version = 2 AND mode = 'full' AND object_prefix IS NOT NULL AND btrim(object_prefix) <> '' AND
     object_prefix ~ ('^projects/' || project_id ||
       '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
     project_storage_key IS NULL AND archive_storage_key = object_prefix || '/snapshot.zip' AND
     archive_size_bytes IS NOT NULL AND archive_size_bytes > 0 AND
     archive_checksum IS NOT NULL AND archive_checksum ~ '^[0-9a-f]{64}$' AND
     project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
     project_checksum IS NOT NULL AND project_checksum ~ '^[0-9a-f]{64}$' AND
     manifest_storage_key = object_prefix || '/manifest.json' AND
     manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
     manifest_checksum IS NOT NULL AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
     total_size_bytes IS NOT NULL AND total_size_bytes > 0 AND object_count = 2 AND
     asset_count IS NOT NULL AND blob_count IS NOT NULL)
    """
  end

  defp full_ready_accounting_check([1]) do
    """
    mode <> 'full' OR lifecycle_state <> 'ready' OR
    (total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
     accounted_size_bytes = total_size_bytes AND
     total_size_bytes = project_size_bytes + manifest_size_bytes + asset_blob_size_bytes)
    """
  end

  defp full_ready_accounting_check([1, 2]) do
    """
    mode <> 'full' OR lifecycle_state <> 'ready' OR
    (format_version = 1 AND total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
     accounted_size_bytes = total_size_bytes AND
     total_size_bytes = project_size_bytes + manifest_size_bytes + asset_blob_size_bytes) OR
    (format_version = 2 AND total_size_bytes IS NOT NULL AND archive_size_bytes IS NOT NULL AND
     manifest_size_bytes IS NOT NULL AND accounted_size_bytes = total_size_bytes AND
     total_size_bytes = archive_size_bytes + manifest_size_bytes)
    """
  end

  defp replace_claim_constraint(versions) do
    drop constraint(
           :snapshot_object_publication_claims,
           :snapshot_object_publication_claims_identity
         )

    prefix =
      if versions == [1],
        do: "object-sets/v1",
        else: "(object-sets/v1|archives/v2)"

    create constraint(
             :snapshot_object_publication_claims,
             :snapshot_object_publication_claims_identity,
             check: """
             object_prefix ~ '^projects/[1-9][0-9]*/snapshots/#{prefix}/ready/[A-Za-z0-9_-]{16}$' AND
             inventory_digest ~ '^[0-9a-f]{64}$' AND
             status IN ('staging', 'staged', 'publishing', 'published', 'poisoned') AND
             storage_reservation_id_snapshot > 0 AND
             ((status IN ('staging', 'publishing') AND lease_expires_at IS NOT NULL) OR
              (status IN ('staged', 'published', 'poisoned') AND lease_expires_at IS NULL))
             """
           )
  end

  defp replace_reservation_constraint(versions) do
    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_cleanup_object_prefix
         )

    build_v2 =
      if versions == [1, 2] do
        """
        OR (kind = 'snapshot_build' AND cleanup_object_prefix ~
          '^projects/[1-9][0-9]*/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$' AND
          cleanup_object_prefix LIKE
            'projects/' || project_id_snapshot || '/snapshots/archives/v2/ready/%')
        """
      else
        ""
      end

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_cleanup_object_prefix,
             check: """
             ((kind IN ('snapshot_build', 'linked_to_full_conversion') AND cleanup_object_prefix ~
                 '^projects/[1-9][0-9]*/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$' AND
                cleanup_object_prefix LIKE
                  'projects/' || project_id_snapshot || '/snapshots/object-sets/v1/ready/%')
              #{build_v2}) OR
             (kind IN ('restore_staging', 'snapshot_export') AND cleanup_object_prefix = storage_namespace)
             """
           )
  end

  defp replace_cleanup_namespace_constraint(versions) do
    drop constraint(
           :storage_cleanup_ownership_namespaces,
           :storage_cleanup_ownership_namespaces_canonical_prefix
         )

    snapshot_prefix =
      if versions == [1],
        do: "object-sets/v1",
        else: "(object-sets/v1|archives/v2)"

    create constraint(
             :storage_cleanup_ownership_namespaces,
             :storage_cleanup_ownership_namespaces_canonical_prefix,
             check: """
             object_prefix ~
               '^projects/[1-9][0-9]*/snapshots/#{snapshot_prefix}/(staging|ready)/[A-Za-z0-9_-]{16}$' OR
             object_prefix ~
               '^projects/[1-9][0-9]*/storage-reservations/v1/(snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             """
           )
  end

  defp replace_cleanup_intent_constraint(versions) do
    drop constraint(:snapshot_cleanup_intents, :snapshot_cleanup_intents_identity)

    v2_prefixes =
      if versions == [1, 2] do
        """
        OR (ready_prefix ~ ('^projects/' || project_id_snapshot ||
              '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
            staging_prefix ~ ('^projects/' || project_id_snapshot ||
              '/snapshots/archives/v2/staging/[A-Za-z0-9_-]{16}$'))
        """
      else
        ""
      end

    create constraint(:snapshot_cleanup_intents, :snapshot_cleanup_intents_identity,
             check: """
             workspace_id_snapshot > 0 AND project_id_snapshot > 0 AND
             project_snapshot_id_snapshot > 0 AND deletion_generation > 0 AND
             mode IN ('full', 'linked') AND
             origin IN ('user', 'daily', 'pre_restore', 'post_restore') AND
             reason IN ('user_delete', 'retention', 'expired_build',
               'project_hard_delete', 'workspace_hard_delete') AND
             authority_kind IN ('user', 'system') AND
             ((authority_kind = 'user' AND authority_actor_id IS NOT NULL AND authority_actor_id > 0) OR
              (authority_kind = 'system' AND authority_actor_id IS NULL)) AND
             ((ready_prefix ~ ('^projects/' || project_id_snapshot ||
                 '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
               staging_prefix ~ ('^projects/' || project_id_snapshot ||
                 '/snapshots/object-sets/v1/staging/[A-Za-z0-9_-]{16}$'))
              #{v2_prefixes}) AND
             inventory_digest ~ '^[0-9a-f]{64}$' AND object_count > 0 AND
             estimated_cleanup_bytes >= 0 AND cardinality(storage_keys) = object_count AND
             status IN ('pending', 'processing', 'retrying', 'completed', 'terminal') AND
             retry_count >= 0 AND processing_generation >= 0 AND
             required_delete_passes = (CASE WHEN reason = 'expired_build' THEN 2 ELSE 1 END) AND
             completed_delete_passes >= 0 AND completed_delete_passes <= required_delete_passes AND
             ((required_delete_passes = 1 AND next_delete_pass_at IS NULL) OR
              (required_delete_passes = 2 AND
               ((completed_delete_passes = 0 AND next_delete_pass_at IS NULL) OR
                (completed_delete_passes > 0 AND next_delete_pass_at IS NOT NULL)))) AND
             ((status = 'completed' AND cardinality(remaining_storage_keys) = 0 AND completed_at IS NOT NULL) OR
              (status = 'terminal' AND cardinality(remaining_storage_keys) > 0 AND terminal_at IS NOT NULL) OR
              (status IN ('pending', 'processing', 'retrying') AND
               cardinality(remaining_storage_keys) > 0 AND completed_at IS NULL AND terminal_at IS NULL)) AND
             ((status = 'completed' AND completed_delete_passes = required_delete_passes) OR
              (status <> 'completed' AND completed_delete_passes < required_delete_passes))
             """
           )
  end

  defp replace_cleanup_ownership_function(versions) do
    snapshot_prefix =
      if versions == [1],
        do: "object-sets/v1",
        else: "(?:object-sets/v1|archives/v2)"

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_capture_storage_cleanup_ownership_receipt()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM unnest(NEW.storage_keys) AS storage_key
        WHERE storage_key ~
          '^projects/[1-9][0-9]*/snapshots/#{snapshot_prefix}/(?:staging|ready)/[A-Za-z0-9_-]{16}/' OR
          storage_key ~
          '^projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
      ) THEN
        INSERT INTO storage_cleanup_ownership_receipts
          (cleanup_request_id, storage_keys, recorded_at)
        VALUES (NEW.id, NEW.storage_keys, NEW.inserted_at);

        INSERT INTO storage_cleanup_ownership_namespaces
          (cleanup_request_id, object_prefix)
        SELECT NEW.id, object_prefix
        FROM (
          SELECT substring(storage_key FROM
            '^(projects/[1-9][0-9]*/snapshots/#{snapshot_prefix}/(?:staging|ready)/[A-Za-z0-9_-]{16})/'
          ) AS object_prefix
          FROM unnest(NEW.storage_keys) AS storage_key
          UNION
          SELECT substring(storage_key FROM
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
    """)
  end
end
