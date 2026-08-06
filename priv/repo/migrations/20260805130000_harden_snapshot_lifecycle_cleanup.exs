defmodule Storyarn.Repo.Migrations.HardenSnapshotLifecycleCleanup do
  use Ecto.Migration

  def up do
    Storyarn.Release.assert_snapshot_lifecycle_migration_authorized!()

    alter table(:project_snapshots) do
      add :origin, :string, null: false, default: "user"
      add :expires_at, :utc_datetime
      add :lifecycle_generation, :bigint, null: false, default: 1
      add :deletion_requested_at, :utc_datetime
    end

    create index(:project_snapshots, [:expires_at, :id],
             where: "expires_at IS NOT NULL",
             name: :project_snapshots_retention_idx
           )

    create constraint(:project_snapshots, :project_snapshots_origin_retention,
             check: """
             (origin = 'user' AND expires_at IS NULL) OR
             (origin IN ('daily', 'pre_restore', 'post_restore') AND expires_at IS NOT NULL)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_lifecycle_generation,
             check: "lifecycle_generation > 0"
           )

    drop constraint(:project_snapshots, :project_snapshots_ready_accounting)
    drop constraint(:project_snapshots, :project_snapshots_ready_object_set)
    drop constraint(:project_snapshots, :project_snapshots_full_ready_accounting)
    drop constraint(:project_snapshots, :project_snapshots_linked_ready_accounting)
    drop constraint(:project_snapshots, :project_snapshots_build_timestamps)

    create constraint(:project_snapshots, :project_snapshots_ready_accounting,
             check: """
             lifecycle_state <> 'ready' OR
             (mode IS NOT NULL AND integrity_state IS NOT NULL AND
              accounted_size_bytes IS NOT NULL AND asset_blob_size_bytes IS NOT NULL AND
              accounting_version IS NOT NULL AND accounting_generation IS NOT NULL AND
              accounting_measured_at IS NOT NULL)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_ready_object_set,
             check: """
             lifecycle_state <> 'ready' OR
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
             mode <> 'full' OR lifecycle_state <> 'ready' OR
             (total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
              accounted_size_bytes = total_size_bytes AND
              total_size_bytes = project_size_bytes + manifest_size_bytes + asset_blob_size_bytes)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_linked_ready_accounting,
             check: """
             mode <> 'linked' OR lifecycle_state <> 'ready' OR
             (total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
              accounted_size_bytes = total_size_bytes AND
              total_size_bytes = project_size_bytes + manifest_size_bytes AND
              blob_count = 0 AND object_count = 2)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_build_timestamps,
             check: """
             (lifecycle_state = 'pending' AND ready_at IS NULL AND cancelled_at IS NULL AND
              deletion_requested_at IS NULL) OR
             (lifecycle_state = 'building' AND building_started_at IS NOT NULL AND
              ready_at IS NULL AND cancelled_at IS NULL AND deletion_requested_at IS NULL) OR
             (lifecycle_state = 'verifying' AND building_started_at IS NOT NULL AND
              verifying_started_at IS NOT NULL AND ready_at IS NULL AND cancelled_at IS NULL AND
              deletion_requested_at IS NULL) OR
             (lifecycle_state = 'ready' AND building_started_at IS NOT NULL AND
              verifying_started_at IS NOT NULL AND ready_at IS NOT NULL AND
              cancelled_at IS NULL AND deletion_requested_at IS NULL) OR
             (lifecycle_state = 'failed' AND ready_at IS NULL AND cancelled_at IS NULL AND
              deletion_requested_at IS NULL) OR
             (lifecycle_state = 'cancelled' AND cancelled_at IS NOT NULL AND ready_at IS NULL AND
              deletion_requested_at IS NULL) OR
             (lifecycle_state = 'deleting' AND deletion_requested_at IS NOT NULL)
             """
           )

    execute("""
    CREATE FUNCTION storyarn_guard_project_snapshot_lifecycle()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      same_generation_transition boolean;
      next_generation_transition boolean;
    BEGIN
      IF TG_OP = 'INSERT' THEN
        NEW.state_updated_at := date_trunc('second', timezone('UTC', clock_timestamp()));
        RETURN NEW;
      END IF;

      same_generation_transition :=
        NEW.lifecycle_generation = OLD.lifecycle_generation AND (
          NEW.lifecycle_state = OLD.lifecycle_state OR
          (OLD.lifecycle_state = 'pending' AND NEW.lifecycle_state IN ('building', 'cancelled')) OR
          (OLD.lifecycle_state = 'building' AND NEW.lifecycle_state IN ('verifying', 'failed', 'cancelled')) OR
          (OLD.lifecycle_state = 'verifying' AND NEW.lifecycle_state IN ('ready', 'failed', 'cancelled'))
        );

      next_generation_transition :=
        NEW.lifecycle_generation = OLD.lifecycle_generation + 1 AND (
          (NEW.lifecycle_state = 'deleting' AND OLD.lifecycle_state <> 'deleting') OR
          (NEW.lifecycle_state = 'pending' AND OLD.lifecycle_state IN ('building', 'verifying', 'failed')) OR
          (NEW.lifecycle_state = OLD.lifecycle_state AND
           OLD.lifecycle_state IN ('pending', 'building', 'verifying') AND
           OLD.cancel_requested_at IS NULL AND NEW.cancel_requested_at IS NOT NULL)
        );

      IF NOT (same_generation_transition OR next_generation_transition) THEN
        RAISE EXCEPTION 'project snapshot lifecycle transition is stale or invalid'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      NEW.state_updated_at := GREATEST(
        OLD.state_updated_at,
        date_trunc('second', timezone('UTC', clock_timestamp()))
      );

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER project_snapshots_lifecycle_guard
    BEFORE INSERT OR UPDATE ON project_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_project_snapshot_lifecycle()
    """)

    alter table(:storage_cleanup_requests) do
      add :owner_kind, :string, null: false, default: "storage_compensation"
      add :owner_token, :uuid
    end

    create index(:storage_cleanup_requests, [:owner_kind, :inserted_at, :id])

    create unique_index(:storage_cleanup_requests, [:owner_token],
             where: "owner_token IS NOT NULL"
           )

    create constraint(:storage_cleanup_requests, :storage_cleanup_requests_owner,
             check: """
             (owner_kind = 'storage_compensation' AND owner_token IS NULL) OR
             (owner_kind = 'snapshot_lifecycle' AND owner_token IS NOT NULL)
             """
           )

    create table(:snapshot_cleanup_intents) do
      add :project_snapshot_id, references(:project_snapshots, on_delete: :nilify_all)

      add :cleanup_request_id, references(:storage_cleanup_requests, on_delete: :restrict),
        null: false

      add :workspace_id_snapshot, :bigint, null: false
      add :project_id_snapshot, :bigint, null: false
      add :project_snapshot_id_snapshot, :bigint, null: false
      add :deletion_generation, :bigint, null: false
      add :mode, :string, null: false
      add :origin, :string, null: false
      add :reason, :string, null: false
      add :authority_kind, :string, null: false
      add :authority_actor_id, :bigint
      add :ready_prefix, :string, size: 500, null: false
      add :staging_prefix, :string, size: 500, null: false
      add :storage_keys, {:array, :text}, null: false
      add :remaining_storage_keys, {:array, :text}, null: false
      add :inventory_digest, :string, size: 64, null: false
      add :object_count, :integer, null: false
      add :estimated_cleanup_bytes, :bigint, null: false
      add :status, :string, null: false
      add :retry_count, :integer, null: false, default: 0
      add :required_delete_passes, :smallint, null: false
      add :completed_delete_passes, :smallint, null: false, default: 0
      add :processing_generation, :bigint, null: false, default: 0
      add :next_delete_pass_at, :utc_datetime
      add :last_error_code, :string
      add :requested_at, :utc_datetime, null: false
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :terminal_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:snapshot_cleanup_intents, [:project_snapshot_id_snapshot])
    create unique_index(:snapshot_cleanup_intents, [:cleanup_request_id])
    create index(:snapshot_cleanup_intents, [:status, :inserted_at, :id])

    create constraint(:snapshot_cleanup_intents, :snapshot_cleanup_intents_identity,
             check: """
             workspace_id_snapshot > 0 AND project_id_snapshot > 0 AND
             project_snapshot_id_snapshot > 0 AND deletion_generation > 0 AND
             mode IN ('full', 'linked') AND
             origin IN ('user', 'daily', 'pre_restore', 'post_restore') AND
             reason IN
               ('user_delete', 'retention', 'expired_build',
                'project_hard_delete', 'workspace_hard_delete') AND
             authority_kind IN ('user', 'system') AND
             ((authority_kind = 'user' AND authority_actor_id IS NOT NULL AND authority_actor_id > 0) OR
              (authority_kind = 'system' AND authority_actor_id IS NULL)) AND
             ready_prefix ~ ('^projects/' || project_id_snapshot ||
               '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
             staging_prefix ~ ('^projects/' || project_id_snapshot ||
               '/snapshots/object-sets/v1/staging/[A-Za-z0-9_-]{16}$') AND
             inventory_digest ~ '^[0-9a-f]{64}$' AND object_count > 0 AND
             estimated_cleanup_bytes >= 0 AND cardinality(storage_keys) = object_count AND
             status IN ('pending', 'processing', 'retrying', 'completed', 'terminal') AND
             retry_count >= 0 AND processing_generation >= 0 AND
             required_delete_passes =
               (CASE WHEN reason = 'expired_build' THEN 2 ELSE 1 END) AND
             completed_delete_passes >= 0 AND
             completed_delete_passes <= required_delete_passes AND
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

    execute("""
    CREATE FUNCTION storyarn_guard_snapshot_cleanup_intent()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      pass_boundary boolean;
      final_completion boolean;
      processing_claim boolean;
    BEGIN
      IF TG_OP = 'INSERT' THEN
        IF NEW.remaining_storage_keys IS DISTINCT FROM NEW.storage_keys OR
           NEW.status <> 'pending' OR NEW.retry_count <> 0 OR
           NEW.completed_delete_passes <> 0 OR NEW.next_delete_pass_at IS NOT NULL OR
           NEW.processing_generation <> 0 OR
           array_position(NEW.storage_keys, NULL) IS NOT NULL OR
           cardinality(NEW.storage_keys) <> (
             SELECT count(DISTINCT storage_key)
             FROM unnest(NEW.storage_keys) AS keys(storage_key)
           ) THEN
          RAISE EXCEPTION 'snapshot cleanup initial inventory must be exact, non-null, and unique'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        RETURN NEW;
      END IF;

      pass_boundary :=
        OLD.reason = 'expired_build' AND
        OLD.status = 'processing' AND NEW.status = 'retrying' AND
        OLD.completed_delete_passes = 0 AND NEW.completed_delete_passes = 1 AND
        NEW.required_delete_passes = 2 AND
        NEW.remaining_storage_keys = NEW.storage_keys;

      IF pass_boundary THEN
        NEW.next_delete_pass_at :=
          date_trunc('second', timezone('UTC', clock_timestamp())) + interval '15 minutes 1 second';
      END IF;

      processing_claim :=
        NEW.status = 'processing' AND OLD.status IN ('pending', 'retrying', 'processing') AND
        NEW.processing_generation = OLD.processing_generation + 1 AND
        NEW.remaining_storage_keys IS NOT DISTINCT FROM OLD.remaining_storage_keys AND
        NEW.retry_count = OLD.retry_count AND
        NEW.completed_delete_passes = OLD.completed_delete_passes AND
        NEW.next_delete_pass_at IS NOT DISTINCT FROM OLD.next_delete_pass_at AND
        NEW.completed_at IS NOT DISTINCT FROM OLD.completed_at AND
        NEW.terminal_at IS NOT DISTINCT FROM OLD.terminal_at;

      IF processing_claim AND OLD.completed_delete_passes > 0 AND
         (OLD.next_delete_pass_at IS NULL OR
          OLD.next_delete_pass_at > timezone('UTC', clock_timestamp())) THEN
        RAISE EXCEPTION 'snapshot cleanup next delete pass is not eligible yet'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      final_completion :=
        OLD.status = 'processing' AND NEW.status = 'completed' AND
        NEW.completed_delete_passes = OLD.completed_delete_passes + 1 AND
        NEW.completed_delete_passes = NEW.required_delete_passes AND
        cardinality(NEW.remaining_storage_keys) = 0;

      IF NEW.cleanup_request_id IS DISTINCT FROM OLD.cleanup_request_id OR
         NEW.workspace_id_snapshot IS DISTINCT FROM OLD.workspace_id_snapshot OR
         NEW.project_id_snapshot IS DISTINCT FROM OLD.project_id_snapshot OR
         NEW.project_snapshot_id_snapshot IS DISTINCT FROM OLD.project_snapshot_id_snapshot OR
         NEW.deletion_generation IS DISTINCT FROM OLD.deletion_generation OR
         NEW.mode IS DISTINCT FROM OLD.mode OR NEW.origin IS DISTINCT FROM OLD.origin OR
         NEW.reason IS DISTINCT FROM OLD.reason OR
         NEW.authority_kind IS DISTINCT FROM OLD.authority_kind OR
         NEW.authority_actor_id IS DISTINCT FROM OLD.authority_actor_id OR
         NEW.ready_prefix IS DISTINCT FROM OLD.ready_prefix OR
         NEW.staging_prefix IS DISTINCT FROM OLD.staging_prefix OR
         NEW.storage_keys IS DISTINCT FROM OLD.storage_keys OR
         NEW.inventory_digest IS DISTINCT FROM OLD.inventory_digest OR
         NEW.object_count IS DISTINCT FROM OLD.object_count OR
         NEW.estimated_cleanup_bytes IS DISTINCT FROM OLD.estimated_cleanup_bytes OR
         NEW.required_delete_passes IS DISTINCT FROM OLD.required_delete_passes OR
         NEW.requested_at IS DISTINCT FROM OLD.requested_at OR
         NEW.inserted_at IS DISTINCT FROM OLD.inserted_at THEN
        RAISE EXCEPTION 'snapshot cleanup intent identity is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.completed_delete_passes IS DISTINCT FROM OLD.completed_delete_passes AND
         NOT (pass_boundary OR final_completion) THEN
        RAISE EXCEPTION 'snapshot cleanup delete passes can only advance at an exact boundary'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF (NEW.status = 'processing' AND NOT processing_claim) OR
         (NEW.processing_generation IS DISTINCT FROM OLD.processing_generation AND
          NOT processing_claim) THEN
        RAISE EXCEPTION 'snapshot cleanup processing generation must advance on an exact claim'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.next_delete_pass_at IS DISTINCT FROM OLD.next_delete_pass_at AND
         NOT pass_boundary THEN
        RAISE EXCEPTION 'snapshot cleanup next pass timestamp can only be assigned at the pass boundary'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NOT (
        NEW.status = OLD.status OR
        (OLD.status IN ('pending', 'retrying') AND NEW.status IN ('processing', 'terminal')) OR
        (OLD.status = 'processing' AND NEW.status IN ('retrying', 'completed', 'terminal')) OR
        (OLD.status = 'terminal' AND NEW.status = 'retrying' AND
         NEW.retry_count = OLD.retry_count AND NEW.terminal_at IS NULL AND
         NEW.completed_at IS NULL AND cardinality(NEW.remaining_storage_keys) > 0)
      ) THEN
        RAISE EXCEPTION 'snapshot cleanup intent state cannot regress'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF array_position(NEW.remaining_storage_keys, NULL) IS NOT NULL OR
         cardinality(NEW.remaining_storage_keys) <> (
           SELECT count(DISTINCT storage_key)
           FROM unnest(NEW.remaining_storage_keys) AS keys(storage_key)
         ) OR
         EXISTS (
           SELECT storage_key
           FROM unnest(NEW.remaining_storage_keys) AS new_keys(storage_key)
           EXCEPT
           SELECT storage_key
           FROM unnest(OLD.remaining_storage_keys) AS old_keys(storage_key)
         ) AND NOT pass_boundary THEN
        RAISE EXCEPTION 'snapshot cleanup remaining inventory can only shrink'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER snapshot_cleanup_intents_guard
    BEFORE INSERT OR UPDATE ON snapshot_cleanup_intents
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_snapshot_cleanup_intent()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS snapshot_cleanup_intents_guard ON snapshot_cleanup_intents")
    execute("DROP FUNCTION IF EXISTS storyarn_guard_snapshot_cleanup_intent()")
    drop table(:snapshot_cleanup_intents)

    drop constraint(:storage_cleanup_requests, :storage_cleanup_requests_owner)

    drop_if_exists unique_index(:storage_cleanup_requests, [:owner_token],
                     where: "owner_token IS NOT NULL"
                   )

    drop_if_exists index(:storage_cleanup_requests, [:owner_kind, :inserted_at, :id])

    alter table(:storage_cleanup_requests) do
      remove :owner_token
      remove :owner_kind
    end

    execute("DROP TRIGGER IF EXISTS project_snapshots_lifecycle_guard ON project_snapshots")
    execute("DROP FUNCTION IF EXISTS storyarn_guard_project_snapshot_lifecycle()")

    drop constraint(:project_snapshots, :project_snapshots_origin_retention)
    drop constraint(:project_snapshots, :project_snapshots_lifecycle_generation)

    drop constraint(:project_snapshots, :project_snapshots_ready_accounting)
    drop constraint(:project_snapshots, :project_snapshots_ready_object_set)
    drop constraint(:project_snapshots, :project_snapshots_full_ready_accounting)
    drop constraint(:project_snapshots, :project_snapshots_linked_ready_accounting)
    drop constraint(:project_snapshots, :project_snapshots_build_timestamps)

    drop_if_exists index(:project_snapshots, [:expires_at, :id],
                     name: :project_snapshots_retention_idx
                   )

    alter table(:project_snapshots) do
      remove :deletion_requested_at
      remove :lifecycle_generation
      remove :expires_at
      remove :origin
    end

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

    create constraint(:project_snapshots, :project_snapshots_linked_ready_accounting,
             check: """
             mode <> 'linked' OR lifecycle_state NOT IN ('ready', 'deleting') OR
             (total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
              accounted_size_bytes = total_size_bytes AND
              total_size_bytes = project_size_bytes + manifest_size_bytes AND
              blob_count = 0 AND object_count = 2)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_build_timestamps,
             check: """
             (lifecycle_state = 'pending' AND ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'building' AND building_started_at IS NOT NULL AND
              ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'verifying' AND building_started_at IS NOT NULL AND
              verifying_started_at IS NOT NULL AND ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'ready' AND building_started_at IS NOT NULL AND
              verifying_started_at IS NOT NULL AND ready_at IS NOT NULL AND
              cancelled_at IS NULL) OR
             (lifecycle_state = 'failed' AND ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'cancelled' AND cancelled_at IS NOT NULL AND ready_at IS NULL) OR
             (lifecycle_state = 'deleting' AND ready_at IS NOT NULL)
             """
           )
  end
end
