defmodule Storyarn.Repo.Migrations.FenceStorageCleanupWriters do
  use Ecto.Migration

  @authorization_key :storyarn_exact_multipart_cleanup_cutover_authorized_v1

  def up do
    assert_release_authorized!()
    current_prefix = assert_current_prefix!()
    lock_and_assert_cleanup_jobs_quiescent!(current_prefix)

    # Earlier development builds installed these same indexes in the historical
    # migration. Preserve them while production upgrades add them incrementally.
    execute("""
    CREATE INDEX IF NOT EXISTS storage_cleanup_requests_storage_keys_gin_idx
    ON storage_cleanup_requests USING GIN (storage_keys)
    """)

    install_exact_cleanup_ownership_capture()

    execute("""
    CREATE INDEX IF NOT EXISTS storage_cleanup_ownership_receipts_storage_keys_gin_idx
    ON storage_cleanup_ownership_receipts USING GIN (storage_keys)
    """)

    backfill_exact_cleanup_ownership()
  end

  def down do
    assert_release_authorized!()

    raise Ecto.MigrationError,
          "FenceStorageCleanupWriters is irreversible: older writers do not honor durable cleanup ownership"
  end

  # Older writers do not honor the durable cleanup ownership installed
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
