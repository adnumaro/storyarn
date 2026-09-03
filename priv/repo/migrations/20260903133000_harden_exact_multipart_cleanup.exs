defmodule Storyarn.Repo.Migrations.HardenExactMultipartCleanup do
  use Ecto.Migration

  @authorization_key :storyarn_exact_multipart_cleanup_cutover_authorized_v1
  @namespace_constraint :storage_cleanup_requests_provider_namespace
  @state_constraint :storage_cleanup_requests_multipart_state
  @claim_constraint :storage_cleanup_requests_multipart_claim
  @error_constraint :storage_cleanup_requests_multipart_error
  @upload_shape_constraint :storage_cleanup_multipart_uploads_shape
  @keys_bounded_constraint :storage_cleanup_requests_keys_bounded

  def up do
    assert_release_authorized!()
    current_prefix = assert_current_prefix!()
    lock_and_assert_cleanup_jobs_quiescent!(current_prefix)

    alter table(:storage_cleanup_requests) do
      add :multipart_cleanup_phase, :string
      add :multipart_cleanup_generation, :bigint, null: false, default: 0
      add :multipart_cleanup_cursor, :integer, null: false, default: 0
      add :multipart_cleanup_residue_count, :integer, null: false, default: 0
      add :multipart_cleanup_inventory_complete, :boolean, null: false, default: false
      add :multipart_cleanup_claim_token, :uuid
      add :multipart_cleanup_claim_expires_at, :utc_datetime
      add :multipart_cleanup_failure_count, :integer, null: false, default: 0
      add :multipart_cleanup_next_attempt_at, :utc_datetime
      add :multipart_cleanup_last_error_code, :string, size: 100
    end

    create constraint(:storage_cleanup_requests, @keys_bounded_constraint,
             check: "cardinality(storage_keys) <= 30001"
           )

    execute("""
    CREATE INDEX storage_cleanup_requests_storage_keys_gin_idx
    ON storage_cleanup_requests USING GIN (storage_keys)
    """)

    install_exact_cleanup_ownership_capture()

    execute("""
    CREATE INDEX storage_cleanup_ownership_receipts_storage_keys_gin_idx
    ON storage_cleanup_ownership_receipts USING GIN (storage_keys)
    """)

    backfill_exact_cleanup_ownership()

    # The old aggregate cleanup protocol did not retain provider upload IDs.
    # A request whose namespace was already durably fenced can restart from a
    # fresh read-only discovery pass. An unfenced request cannot be rebound
    # safely to whichever provider happens to be configured at migration time,
    # so keep it visible and fail closed instead.
    execute("""
    UPDATE storage_cleanup_requests
    SET multipart_cleanup_phase =
          CASE
            WHEN provider_namespace_fingerprint ~ '^[0-9a-f]{64}$' THEN 'discover'
            ELSE 'blocked'
          END,
        multipart_cleanup_last_error_code =
          CASE
            WHEN provider_namespace_fingerprint ~ '^[0-9a-f]{64}$' THEN NULL
            ELSE 'legacy_multipart_identity_unbound'
          END
    WHERE multipart_quiescence_started_at IS NOT NULL OR
          multipart_quiescence_not_before IS NOT NULL
    """)

    drop constraint(:storage_cleanup_requests, @namespace_constraint)

    execute("""
    ALTER TABLE storage_cleanup_requests
    ADD CONSTRAINT #{@namespace_constraint}
    CHECK (
      (owner_kind = 'storage_compensation' AND owner_token IS NULL AND (
        (multipart_cleanup_phase IS NULL AND provider_namespace_fingerprint IS NULL) OR
        (multipart_cleanup_phase IS NOT NULL AND
         provider_namespace_fingerprint IS NOT NULL AND
         provider_namespace_fingerprint ~ '^[0-9a-f]{64}$') OR
        (multipart_cleanup_phase = 'blocked' AND
         multipart_cleanup_last_error_code = 'legacy_multipart_identity_unbound' AND
         provider_namespace_fingerprint IS NULL)
      )) OR
      (owner_kind = 'snapshot_lifecycle' AND owner_token IS NOT NULL AND
       provider_namespace_fingerprint IS NOT NULL AND
       provider_namespace_fingerprint ~ '^[0-9a-f]{64}$')
    ) NOT VALID
    """)

    execute("""
    ALTER TABLE storage_cleanup_requests
    ADD CONSTRAINT #{@claim_constraint}
    CHECK (
      (multipart_cleanup_claim_token IS NULL AND
       multipart_cleanup_claim_expires_at IS NULL) OR
      (multipart_cleanup_claim_token IS NOT NULL AND
       multipart_cleanup_claim_expires_at IS NOT NULL)
    ) NOT VALID
    """)

    execute("""
    ALTER TABLE storage_cleanup_requests
    ADD CONSTRAINT #{@error_constraint}
    CHECK (
      multipart_cleanup_last_error_code IS NULL OR
      (octet_length(multipart_cleanup_last_error_code) BETWEEN 1 AND 100 AND
       multipart_cleanup_last_error_code ~ '^[a-z][a-z0-9_]*$')
    ) NOT VALID
    """)

    execute("""
    ALTER TABLE storage_cleanup_requests
    ADD CONSTRAINT #{@state_constraint}
    CHECK (
      multipart_cleanup_generation >= 0 AND
      multipart_cleanup_cursor >= 0 AND
      multipart_cleanup_residue_count BETWEEN 0 AND 1000 AND
      multipart_cleanup_failure_count BETWEEN 0 AND 1000 AND
      (
        (multipart_cleanup_phase IS NULL AND
         multipart_cleanup_generation = 0 AND
         multipart_cleanup_cursor = 0 AND
         multipart_cleanup_residue_count = 0 AND
         multipart_cleanup_inventory_complete = FALSE AND
         multipart_cleanup_failure_count = 0 AND
         multipart_cleanup_claim_token IS NULL AND
         multipart_cleanup_claim_expires_at IS NULL AND
         multipart_cleanup_next_attempt_at IS NULL AND
         multipart_cleanup_last_error_code IS NULL) OR
        (multipart_cleanup_phase IN (
           'discover', 'abort', 'delete', 'verify_inventory',
           'verify_references', 'verify_objects', 'verify_final_inventory'
         ) AND
         provider_namespace_fingerprint IS NOT NULL AND
         provider_namespace_fingerprint ~ '^[0-9a-f]{64}$') OR
        (multipart_cleanup_phase = 'quiet' AND
         multipart_cleanup_inventory_complete = TRUE AND
         provider_namespace_fingerprint IS NOT NULL AND
         provider_namespace_fingerprint ~ '^[0-9a-f]{64}$') OR
        (multipart_cleanup_phase = 'confirmed' AND
         multipart_cleanup_inventory_complete = TRUE AND
         provider_namespace_fingerprint IS NOT NULL AND
         provider_namespace_fingerprint ~ '^[0-9a-f]{64}$' AND
         multipart_cleanup_claim_token IS NULL AND
         multipart_cleanup_claim_expires_at IS NULL AND
         multipart_cleanup_next_attempt_at IS NULL) OR
        (multipart_cleanup_phase = 'blocked' AND
         multipart_cleanup_last_error_code IS NOT NULL AND
         multipart_cleanup_claim_token IS NULL AND
         multipart_cleanup_claim_expires_at IS NULL AND
         multipart_cleanup_next_attempt_at IS NULL)
      )
    ) NOT VALID
    """)

    execute("ALTER TABLE storage_cleanup_requests VALIDATE CONSTRAINT #{@namespace_constraint}")
    execute("ALTER TABLE storage_cleanup_requests VALIDATE CONSTRAINT #{@claim_constraint}")
    execute("ALTER TABLE storage_cleanup_requests VALIDATE CONSTRAINT #{@error_constraint}")
    execute("ALTER TABLE storage_cleanup_requests VALIDATE CONSTRAINT #{@state_constraint}")

    create unique_index(:storage_cleanup_requests, [:multipart_cleanup_claim_token],
             where: "multipart_cleanup_claim_token IS NOT NULL",
             name: :storage_cleanup_requests_multipart_claim_idx
           )

    create index(
             :storage_cleanup_requests,
             [:multipart_cleanup_phase, :multipart_cleanup_next_attempt_at, :id],
             where: "multipart_cleanup_phase IS NOT NULL",
             name: :storage_cleanup_requests_multipart_due_idx
           )

    create table(:storage_cleanup_multipart_uploads) do
      add :cleanup_request_id,
          references(:storage_cleanup_requests,
            on_delete: :delete_all,
            name: :storage_cleanup_multipart_uploads_request_fkey
          ),
          null: false

      add :storage_key, :text, null: false
      add :upload_id, :text, null: false
      add :reference_digest, :string, size: 64, null: false
      add :last_aborted_generation, :bigint
      add :last_absent_generation, :bigint

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :storage_cleanup_multipart_uploads,
             [:cleanup_request_id, :reference_digest],
             name: :storage_cleanup_multipart_uploads_request_digest_idx
           )

    create index(
             :storage_cleanup_multipart_uploads,
             [:cleanup_request_id, :last_aborted_generation, :id],
             name: :storage_cleanup_multipart_uploads_abort_idx
           )

    create index(
             :storage_cleanup_multipart_uploads,
             [:cleanup_request_id, :last_absent_generation, :id],
             name: :storage_cleanup_multipart_uploads_absence_idx
           )

    execute("""
    ALTER TABLE storage_cleanup_multipart_uploads
    ADD CONSTRAINT #{@upload_shape_constraint}
    CHECK (
      octet_length(storage_key) BETWEEN 1 AND 4096 AND
      octet_length(upload_id) BETWEEN 1 AND 4096 AND
      reference_digest ~ '^[0-9a-f]{64}$' AND
      (last_aborted_generation IS NULL OR last_aborted_generation >= 0) AND
      (last_absent_generation IS NULL OR last_absent_generation >= 0)
    )
    """)

    execute("""
    CREATE FUNCTION storyarn_guard_storage_cleanup_multipart_upload_identity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.cleanup_request_id IS DISTINCT FROM OLD.cleanup_request_id OR
         NEW.storage_key IS DISTINCT FROM OLD.storage_key OR
         NEW.upload_id IS DISTINCT FROM OLD.upload_id OR
         NEW.reference_digest IS DISTINCT FROM OLD.reference_digest THEN
        RAISE EXCEPTION 'storage cleanup multipart upload identity is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER storage_cleanup_multipart_uploads_identity_guard
    BEFORE UPDATE OF cleanup_request_id, storage_key, upload_id, reference_digest
    ON storage_cleanup_multipart_uploads
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_storage_cleanup_multipart_upload_identity()
    """)

    execute("""
    CREATE FUNCTION storyarn_guard_storage_cleanup_multipart_upload_ownership()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM storage_cleanup_requests AS request
        WHERE request.id = NEW.cleanup_request_id AND
              (
                NEW.storage_key = ANY(request.storage_keys) OR
                ('__storyarn_force_delete__:' || NEW.storage_key) = ANY(request.storage_keys)
              )
      ) THEN
        RAISE EXCEPTION 'multipart upload key is not owned by its cleanup request'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER storage_cleanup_multipart_uploads_ownership_guard
    BEFORE INSERT OR UPDATE OF cleanup_request_id, storage_key
    ON storage_cleanup_multipart_uploads
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_storage_cleanup_multipart_upload_ownership()
    """)

    execute("""
    CREATE FUNCTION storyarn_guard_storage_cleanup_request_keys_immutable()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.storage_keys IS DISTINCT FROM OLD.storage_keys THEN
        RAISE EXCEPTION 'cleanup request storage keys are immutable after handoff'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.owner_kind IS DISTINCT FROM OLD.owner_kind OR
         NEW.owner_token IS DISTINCT FROM OLD.owner_token OR
         NEW.provider_namespace_fingerprint IS DISTINCT FROM OLD.provider_namespace_fingerprint THEN
        RAISE EXCEPTION 'cleanup request owner identity is immutable after handoff'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER storage_cleanup_requests_retain_multipart_keys
    BEFORE UPDATE OF storage_keys, owner_kind, owner_token, provider_namespace_fingerprint
    ON storage_cleanup_requests
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_storage_cleanup_request_keys_immutable()
    """)
  end

  def down do
    assert_release_authorized!()

    raise Ecto.MigrationError,
          "HardenExactMultipartCleanup is irreversible: the previous binary cannot interpret durable multipart cleanup state"
  end

  # The old binary does not understand the durable multipart state introduced
  # below. The deployment therefore stops every application Machine before the
  # release command enters this transaction. Locking Oban's table closes the
  # final database race: no job may still be executing, and none can
  # transition state until this migration commits.
  defp lock_and_assert_cleanup_jobs_quiescent!(current_prefix) do
    jobs = qualified_table(current_prefix, "oban_jobs")

    repo().query!("SET LOCAL lock_timeout = '5s'")
    repo().query!("LOCK TABLE #{jobs} IN ACCESS EXCLUSIVE MODE")

    case repo().query!("""
         SELECT NOT EXISTS (
           SELECT 1
           FROM #{jobs}
           WHERE state = 'executing'
         )
         """).rows do
      [[true]] ->
        :ok

      [[false]] ->
        raise Ecto.MigrationError,
              "Exact multipart cleanup cutover requires no executing jobs"

      invalid ->
        raise Ecto.MigrationError,
              "Invalid exact multipart cleanup job preflight result: #{inspect(invalid)}"
    end
  end

  # Keep this ABI frozen in the migration. Release.migrate decides whether the
  # one-release acknowledgement is required, then grants only this process tree
  # permission to run the protected DDL.
  defp assert_release_authorized! do
    enforced? =
      Application.get_env(:storyarn, :enforce_snapshot_lifecycle_release_gate, false)

    if enforced? and not release_authorized?() do
      raise "Exact multipart cleanup migration must run through /app/bin/migrate after the stop-the-world deployment boundary"
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
            "Exact multipart cleanup requires its explicit prefix to match current_schema(); requested #{inspect(requested_prefix)}, current #{inspect(current_prefix)}"
    end
  end

  defp validate_prefix!(value) when is_binary(value) and byte_size(value) > 0 do
    if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_$]*\z/, value) do
      value
    else
      raise Ecto.MigrationError, "Unsafe exact multipart cleanup prefix: #{inspect(value)}"
    end
  end

  defp validate_prefix!(value),
    do: raise(Ecto.MigrationError, "Invalid exact multipart cleanup prefix: #{inspect(value)}")

  defp qualified_table(current_prefix, table), do: ~s("#{current_prefix}"."#{table}")

  defp install_exact_cleanup_ownership_capture do
    execute("""
    CREATE OR REPLACE FUNCTION storyarn_capture_storage_cleanup_ownership_receipt()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM unnest(NEW.storage_keys) AS raw_key(storage_key)
        WHERE regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
                '/snapshots/object-sets/v1/' OR
              regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
                '/storage-reservations/v1/linked-to-full-conversion/'
      ) THEN
        RAISE EXCEPTION 'retired v1/linked snapshot cleanup ownership is not accepted'
          USING ERRCODE = 'check_violation';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM unnest(NEW.storage_keys) AS raw_key(storage_key)
        WHERE regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
          '^projects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16}/' OR
          regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
          '^projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' OR
          regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
          '^workspace-snapshot-imports/v1/[1-9][0-9]*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
      ) THEN
        INSERT INTO storage_cleanup_ownership_receipts
          (cleanup_request_id, storage_keys, recorded_at)
        VALUES (NEW.id, NEW.storage_keys, NEW.inserted_at)
        ON CONFLICT (cleanup_request_id) DO NOTHING;

        INSERT INTO storage_cleanup_ownership_namespaces
          (cleanup_request_id, object_prefix)
        SELECT NEW.id, object_prefix
        FROM (
          SELECT substring(
            regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') FROM
            '^(projects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16})/'
          ) AS object_prefix
          FROM unnest(NEW.storage_keys) AS raw_key(storage_key)
          UNION
          SELECT substring(
            regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') FROM
            '^(projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'
          ) AS object_prefix
          FROM unnest(NEW.storage_keys) AS raw_key(storage_key)
        ) AS owned_namespaces
        WHERE object_prefix IS NOT NULL
        ON CONFLICT (cleanup_request_id, object_prefix) DO NOTHING;
      END IF;

      RETURN NEW;
    END;
    $$
    """)
  end

  defp backfill_exact_cleanup_ownership do
    execute("""
    INSERT INTO storage_cleanup_ownership_receipts
      (cleanup_request_id, storage_keys, recorded_at)
    SELECT request.id, request.storage_keys, request.inserted_at
    FROM storage_cleanup_requests AS request
    WHERE EXISTS (
      SELECT 1
      FROM unnest(request.storage_keys) AS raw_key(storage_key)
      WHERE regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
        '^projects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16}/' OR
        regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
        '^projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' OR
        regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') ~
        '^workspace-snapshot-imports/v1/[1-9][0-9]*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
    )
    ON CONFLICT (cleanup_request_id) DO NOTHING
    """)

    execute("""
    INSERT INTO storage_cleanup_ownership_namespaces
      (cleanup_request_id, object_prefix)
    SELECT cleanup_request_id, object_prefix
    FROM (
      SELECT request.id AS cleanup_request_id,
             substring(
               regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') FROM
               '^(projects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16})/'
             ) AS object_prefix
      FROM storage_cleanup_requests AS request,
           unnest(request.storage_keys) AS raw_key(storage_key)
      UNION
      SELECT request.id AS cleanup_request_id,
             substring(
               regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '') FROM
               '^(projects/[1-9][0-9]*/storage-reservations/v1/(?:snapshot-build|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'
             ) AS object_prefix
      FROM storage_cleanup_requests AS request,
           unnest(request.storage_keys) AS raw_key(storage_key)
    ) AS owned_namespaces
    WHERE object_prefix IS NOT NULL
    ON CONFLICT (cleanup_request_id, object_prefix) DO NOTHING
    """)
  end
end
