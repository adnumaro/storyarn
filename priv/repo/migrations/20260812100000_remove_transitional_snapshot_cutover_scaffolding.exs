defmodule Storyarn.Repo.Migrations.RemoveTransitionalSnapshotCutoverScaffolding do
  @moduledoc """
  Removes the one-release compatibility surface left by the v2-only cutover.

  The retired columns were kept nullable and fenced to `NULL` so the previous
  binary could finish a rolling deployment. The worker routing constraint
  served the same purpose for snapshot jobs. This migration verifies that the
  v2-only contract and those fences are still intact under exclusive locks
  before removing them permanently.
  """

  use Ecto.Migration

  @v2_only_migration 20_260_811_180_000
  @authorization_key :storyarn_snapshot_scaffolding_cleanup_authorized_v1
  @active_states ~w(available scheduled executing retryable)
  @retired_workers [
    "Storyarn.Workers.DailySnapshotWorker",
    "Storyarn.Workers.SnapshotRetentionWorker",
    "Storyarn.Workers.RestoreProjectWorker",
    "Storyarn.Workers.RecoverProjectWorker"
  ]
  @worker_routing_check """
  state NOT IN ('available', 'scheduled', 'executing', 'retryable') OR
  (
    worker NOT IN (
      'Storyarn.Workers.DailySnapshotWorker',
      'Storyarn.Workers.SnapshotRetentionWorker',
      'Storyarn.Workers.RestoreProjectWorker',
      'Storyarn.Workers.RecoverProjectWorker'
    ) AND
    (worker <> 'Storyarn.Workers.BuildProjectSnapshotWorker' OR queue = 'snapshot_archives')
  )
  """
  @constraint_probe :storyarn_snapshot_cleanup_20260812100000_contract_probe

  def up do
    assert_release_authorized!()
    current_prefix = assert_current_prefix!()
    assert_v2_only_migration_applied!(current_prefix)
    snapshots = qualified_table(current_prefix, "project_snapshots")
    publication_claims = qualified_table(current_prefix, "snapshot_object_publication_claims")
    reservations = qualified_table(current_prefix, "workspace_storage_reservations")
    cleanup_intents = qualified_table(current_prefix, "snapshot_cleanup_intents")
    jobs = qualified_table(current_prefix, "oban_jobs")

    repo().query!("""
    LOCK TABLE
      #{snapshots},
      #{publication_claims},
      #{reservations},
      #{cleanup_intents},
      #{jobs}
    IN ACCESS EXCLUSIVE MODE
    """)

    assert_transitional_contract!(current_prefix)
    assert_retired_values_absent!(snapshots, reservations)
    assert_snapshot_jobs_canonical!(jobs)

    execute("""
    ALTER TABLE #{snapshots}
      DROP CONSTRAINT project_snapshots_retired_project_storage,
      DROP COLUMN project_storage_key
    """)

    execute("""
    ALTER TABLE #{reservations}
      DROP CONSTRAINT workspace_storage_reservations_source_inventory,
      DROP COLUMN source_asset_count
    """)

    execute("""
    ALTER TABLE #{jobs}
      DROP CONSTRAINT oban_jobs_snapshot_worker_routing
    """)
  end

  def down do
    raise Ecto.MigrationError,
          "RemoveTransitionalSnapshotCutoverScaffolding is irreversible: retired snapshot compatibility must not be reconstructed"
  end

  defp assert_transitional_contract!(current_prefix) do
    assert_column!(current_prefix, "project_snapshots", "project_storage_key")
    assert_column!(current_prefix, "workspace_storage_reservations", "source_asset_count")

    assert_constraint!(
      current_prefix,
      "project_snapshots",
      "project_snapshots_retired_project_storage",
      "project_storage_key IS NULL"
    )

    assert_constraint!(
      current_prefix,
      "workspace_storage_reservations",
      "workspace_storage_reservations_source_inventory",
      "source_asset_count IS NULL"
    )

    assert_constraint!(
      current_prefix,
      "oban_jobs",
      "oban_jobs_snapshot_worker_routing",
      @worker_routing_check
    )

    Enum.each(canonical_v2_checks(), fn {table, constraint, check} ->
      assert_constraint!(current_prefix, table, constraint, check)
    end)
  end

  # Keep these definitions frozen with the migration that installed them. The
  # cleanup must prove the complete v2 database contract before it removes the
  # rolling-deploy fences that protected that contract. The two explicit
  # `ANY (ARRAY[...])` forms reproduce the exact expression trees PostgreSQL
  # stored after that migration altered `project_snapshots.mode`.
  defp canonical_v2_checks do
    [
      {"project_snapshots", "project_snapshots_object_format_version", "format_version = 2"},
      {"project_snapshots", "project_snapshots_archive_format",
       """
       format_version = 2 AND mode = 'full' AND
       archive_storage_key IS NOT NULL AND
       ((lifecycle_state::text = ANY (ARRAY[
           ('pending'::character varying)::text,
           ('failed'::character varying)::text,
           ('cancelled'::character varying)::text,
           ('deleting'::character varying)::text
         ]) AND
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
       """},
      {"project_snapshots", "project_snapshots_object_counts",
       """
       (object_count IS NULL AND asset_count IS NULL AND blob_count IS NULL) OR
       (object_count = 2 AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
        blob_count >= 0 AND asset_count >= blob_count)
       """},
      {"project_snapshots", "project_snapshots_mode", "mode = 'full'"},
      {"project_snapshots", "project_snapshots_mode_integrity",
       """
       mode = 'full' AND
       integrity_state::text = ANY (ARRAY[
         ('unknown'::character varying)::text,
         ('verified'::character varying)::text,
         ('missing'::character varying)::text,
         ('corrupt'::character varying)::text,
         ('incomplete'::character varying)::text
       ])
       """},
      {"project_snapshots", "project_snapshots_accounting_identity",
       """
       format_version = 2 AND mode = 'full' AND
       lifecycle_state IS NOT NULL AND integrity_state IS NOT NULL
       """},
      {"project_snapshots", "project_snapshots_object_target",
       """
       format_version = 2 AND mode = 'full' AND object_prefix IS NOT NULL AND
       object_prefix ~ ('^projects/' || project_id ||
         '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
       archive_storage_key = object_prefix || '/snapshot.zip' AND
       manifest_storage_key IS NOT NULL AND
       manifest_storage_key = object_prefix || '/manifest.json'
       """},
      {"project_snapshots", "project_snapshots_ready_object_set",
       """
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
       """},
      {"project_snapshots", "project_snapshots_full_ready_accounting",
       """
       lifecycle_state <> 'ready' OR
       (total_size_bytes IS NOT NULL AND archive_size_bytes IS NOT NULL AND
        manifest_size_bytes IS NOT NULL AND accounted_size_bytes = total_size_bytes AND
        total_size_bytes = archive_size_bytes + manifest_size_bytes)
       """},
      {"snapshot_object_publication_claims", "snapshot_object_publication_claims_identity",
       """
       object_prefix ~
         '^projects/[1-9][0-9]*/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$' AND
       inventory_digest ~ '^[0-9a-f]{64}$' AND
       status IN ('staging', 'staged', 'publishing', 'published', 'poisoned') AND
       storage_reservation_id_snapshot > 0 AND
       ((status IN ('staging', 'publishing') AND lease_expires_at IS NOT NULL) OR
        (status IN ('staged', 'published', 'poisoned') AND lease_expires_at IS NULL))
       """},
      {"workspace_storage_reservations", "workspace_storage_reservations_kind",
       "kind IN ('snapshot_build', 'restore_staging', 'snapshot_export')"},
      {"workspace_storage_reservations", "workspace_storage_reservations_positive_values",
       """
       ((kind = 'snapshot_export' AND reserved_bytes >= 0) OR
        (kind <> 'snapshot_export' AND reserved_bytes > 0)) AND
       (actual_bytes IS NULL OR (actual_bytes > 0 AND actual_bytes <= reserved_bytes)) AND
       generation > 0 AND accounting_version = 1 AND
       (status <> 'active' OR expires_at > accounting_measured_at)
       """},
      {"workspace_storage_reservations", "workspace_storage_reservations_namespace",
       """
       storage_namespace ~
         '^projects/[1-9][0-9]*/storage-reservations/v1/(snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND
       storage_namespace =
         'projects/' || project_id_snapshot || '/storage-reservations/v1/' ||
         replace(kind, '_', '-') || '/' || lease_token::text
       """},
      {"workspace_storage_reservations", "workspace_storage_reservations_cleanup_object_prefix",
       """
       (kind = 'snapshot_build' AND cleanup_object_prefix ~
          '^projects/[1-9][0-9]*/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$' AND
        cleanup_object_prefix LIKE
          'projects/' || project_id_snapshot || '/snapshots/archives/v2/ready/%') OR
       (kind IN ('restore_staging', 'snapshot_export') AND
        cleanup_object_prefix = storage_namespace)
       """},
      {"snapshot_cleanup_intents", "snapshot_cleanup_intents_identity",
       """
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
       """}
    ]
  end

  defp assert_v2_only_migration_applied!(current_prefix) do
    migrations = qualified_table(current_prefix, "schema_migrations")

    case repo().query!(
           "SELECT to_regclass($1) IS NOT NULL",
           [migrations]
         ).rows do
      [[true]] ->
        case repo().query!(
               "SELECT EXISTS (SELECT 1 FROM #{migrations} WHERE version = $1)",
               [@v2_only_migration]
             ).rows do
          [[true]] ->
            :ok

          [[false]] ->
            raise Ecto.MigrationError,
                  "Snapshot cutover cleanup requires the v2-only migration marker from the preceding release"

          invalid ->
            raise Ecto.MigrationError,
                  "Invalid v2-only migration marker preflight result: #{inspect(invalid)}"
        end

      [[false]] ->
        raise Ecto.MigrationError,
              "Snapshot cutover cleanup requires the schema_migrations history from the preceding release"

      invalid ->
        raise Ecto.MigrationError,
              "Invalid schema_migrations preflight result: #{inspect(invalid)}"
    end
  end

  defp assert_column!(current_prefix, table, column) do
    case repo().query!(
           """
           SELECT EXISTS (
             SELECT 1
             FROM information_schema.columns
             WHERE table_schema = $1 AND table_name = $2 AND column_name = $3
           )
           """,
           [current_prefix, table, column]
         ).rows do
      [[true]] ->
        :ok

      [[false]] ->
        raise Ecto.MigrationError,
              "Snapshot cutover cleanup requires #{table}.#{column} to remain present until this migration removes it"

      invalid ->
        raise Ecto.MigrationError,
              "Invalid snapshot cutover column preflight result: #{inspect(invalid)}"
    end
  end

  defp assert_constraint!(current_prefix, table, constraint, canonical_check) do
    qualified_table = qualified_table(current_prefix, table)

    # PostgreSQL parses the expected expression against the real table and
    # deparses both trees. Exact pg_get_expr equality avoids trusting source
    # whitespace/casts while rejecting any logically broader expression.
    repo().query!("""
    ALTER TABLE #{qualified_table}
    ADD CONSTRAINT #{@constraint_probe} CHECK (#{canonical_check}) NOT VALID
    """)

    result =
      repo().query!(
        """
        SELECT
          actual.convalidated,
          pg_get_expr(actual.conbin, actual.conrelid, false),
          pg_get_expr(probe.conbin, probe.conrelid, false)
        FROM pg_constraint AS actual
        JOIN pg_class AS table_row ON table_row.oid = actual.conrelid
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
        JOIN pg_constraint AS probe
          ON probe.conrelid = actual.conrelid
         AND probe.conname = $4
         AND probe.contype = 'c'
        WHERE namespace_row.nspname = $1
          AND table_row.relname = $2
          AND actual.conname = $3
          AND actual.contype = 'c'
        """,
        [current_prefix, table, constraint, Atom.to_string(@constraint_probe)]
      ).rows

    repo().query!("ALTER TABLE #{qualified_table} DROP CONSTRAINT #{@constraint_probe}")

    case result do
      [[true, canonical, canonical]] ->
        :ok

      [[true, _actual, _expected]] ->
        raise Ecto.MigrationError,
              "Snapshot cutover cleanup requires the canonical #{constraint} definition"

      _missing_or_unvalidated ->
        raise Ecto.MigrationError,
              "Snapshot cutover cleanup requires validated constraint #{constraint} on #{table}"
    end
  end

  defp assert_retired_values_absent!(snapshots, reservations) do
    case repo().query!("""
         SELECT
           NOT EXISTS (
             SELECT 1
             FROM #{snapshots}
             WHERE format_version IS DISTINCT FROM 2
                OR mode IS DISTINCT FROM 'full'
                OR project_storage_key IS NOT NULL
           ),
           NOT EXISTS (
             SELECT 1
             FROM #{reservations}
             WHERE kind = 'linked_to_full_conversion'
                OR source_asset_count IS NOT NULL
           )
         """).rows do
      [[true, true]] ->
        :ok

      [[snapshots_clean?, reservations_clean?]] ->
        raise Ecto.MigrationError,
              "Snapshot cutover cleanup requires canonical v2-only rows; snapshots_clean?=#{snapshots_clean?}, reservations_clean?=#{reservations_clean?}"

      invalid ->
        raise Ecto.MigrationError,
              "Invalid snapshot cutover data preflight result: #{inspect(invalid)}"
    end
  end

  defp assert_snapshot_jobs_canonical!(jobs) do
    case repo().query!(
           """
           SELECT NOT EXISTS (
             SELECT 1
             FROM #{jobs}
             WHERE state = ANY($1)
               AND (
                 worker = ANY($2) OR
                 (worker = 'Storyarn.Workers.BuildProjectSnapshotWorker' AND
                  queue IS DISTINCT FROM 'snapshot_archives')
               )
           )
           """,
           [@active_states, @retired_workers]
         ).rows do
      [[true]] ->
        :ok

      [[false]] ->
        raise Ecto.MigrationError,
              "Snapshot cutover cleanup requires no active retired or misrouted snapshot workers"

      invalid ->
        raise Ecto.MigrationError,
              "Invalid snapshot worker preflight result: #{inspect(invalid)}"
    end
  end

  # Keep this authorization ABI frozen in the migration. The release task
  # decides from the schema state that existed before Ecto starts migrating
  # whether a fresh bootstrap or a completed v2-only rollout may proceed.
  defp assert_release_authorized! do
    enforced? =
      Application.get_env(:storyarn, :enforce_snapshot_lifecycle_release_gate, false)

    if enforced? and not release_authorized?() do
      raise "Snapshot scaffolding cleanup migration must run through /app/bin/migrate after a completed v2-only release boundary"
    end
  end

  defp release_authorized? do
    Process.get(@authorization_key, false) == true or
      Enum.any?(List.wrap(Process.get(:"$callers")), &authorized_caller?/1)
  end

  defp authorized_caller?(pid) when is_pid(pid) and node(pid) == node() do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        List.keyfind(dictionary, @authorization_key, 0) == {@authorization_key, true}

      nil ->
        false
    end
  end

  defp authorized_caller?(_pid), do: false

  defp assert_current_prefix! do
    current_prefix =
      case repo().query!("SELECT current_schema()").rows do
        [[value]] ->
          validate_prefix!(value)

        invalid ->
          raise Ecto.MigrationError, "Invalid current migration prefix: #{inspect(invalid)}"
      end

    requested_prefix = validate_prefix!(prefix() || current_prefix)

    if requested_prefix == current_prefix do
      current_prefix
    else
      raise Ecto.MigrationError,
            "Snapshot cutover cleanup requires its explicit prefix to match current_schema(); requested #{inspect(requested_prefix)}, current #{inspect(current_prefix)}"
    end
  end

  defp validate_prefix!(value) when is_binary(value) and byte_size(value) > 0 do
    if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_$]*\z/, value) do
      value
    else
      raise Ecto.MigrationError, "Unsafe snapshot cutover cleanup prefix: #{inspect(value)}"
    end
  end

  defp validate_prefix!(value),
    do: raise(Ecto.MigrationError, "Invalid snapshot cutover cleanup prefix: #{inspect(value)}")

  defp qualified_table(current_prefix, table), do: ~s("#{current_prefix}"."#{table}")
end
