defmodule Storyarn.Repo.Migrations.AddRestoreCleanupStorageKeys do
  @moduledoc """
  Persists the exact temporary-object inventory of an active restore.

  The inventory is retained after settlement as audit evidence. Only active
  restore staging rows are indexed because that is the set storage cleanup must
  fence before deleting a provider key.
  """

  use Ecto.Migration

  @max_cleanup_inventory_count 30_000
  @max_cleanup_inventory_bytes 16 * 1024 * 1024

  def up do
    alter table(:workspace_storage_reservations) do
      add :cleanup_storage_keys, {:array, :text}
    end

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_cleanup_storage_keys,
             check: """
             (
               cleanup_storage_keys IS NULL AND
               (kind <> 'restore_staging' OR storage_started_at IS NULL OR status <> 'active')
             ) OR (
               kind = 'restore_staging' AND storage_started_at IS NOT NULL AND
               cleanup_storage_keys IS NOT NULL AND
               cardinality(cleanup_storage_keys) > 0 AND
               cardinality(cleanup_storage_keys) <= #{@max_cleanup_inventory_count} AND
               array_position(cleanup_storage_keys, NULL) IS NULL AND
               array_position(cleanup_storage_keys, '') IS NULL AND
               cleanup_inventory_count = cardinality(cleanup_storage_keys) AND
               octet_length(array_to_string(cleanup_storage_keys, '')) <=
                 #{@max_cleanup_inventory_bytes}
             )
             """
           )

    execute("""
    CREATE INDEX workspace_storage_reservations_active_restore_cleanup_keys_idx
    ON workspace_storage_reservations USING GIN (cleanup_storage_keys)
    WHERE status = 'active' AND kind = 'restore_staging' AND
          storage_started_at IS NOT NULL
    """)

    execute("""
    CREATE FUNCTION storyarn_guard_restore_cleanup_storage_keys()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF OLD.cleanup_storage_keys IS NOT NULL AND
         NEW.cleanup_storage_keys IS DISTINCT FROM OLD.cleanup_storage_keys THEN
        RAISE EXCEPTION 'restore cleanup storage keys are immutable once persisted'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER workspace_storage_reservations_cleanup_storage_keys_immutable
    BEFORE UPDATE OF cleanup_storage_keys ON workspace_storage_reservations
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_restore_cleanup_storage_keys()
    """)
  end

  def down do
    assert_no_persisted_restore_cleanup_keys!()

    execute("""
    DROP TRIGGER workspace_storage_reservations_cleanup_storage_keys_immutable
    ON workspace_storage_reservations
    """)

    execute("DROP FUNCTION storyarn_guard_restore_cleanup_storage_keys()")

    execute("DROP INDEX workspace_storage_reservations_active_restore_cleanup_keys_idx")

    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_cleanup_storage_keys
         )

    alter table(:workspace_storage_reservations) do
      remove :cleanup_storage_keys, {:array, :text}
    end
  end

  defp assert_no_persisted_restore_cleanup_keys! do
    case repo().query!("""
         SELECT EXISTS (
           SELECT 1
           FROM workspace_storage_reservations
           WHERE cleanup_storage_keys IS NOT NULL
         )
         """).rows do
      [[false]] ->
        :ok

      [[true]] ->
        raise Ecto.MigrationError,
              "AddRestoreCleanupStorageKeys cannot be rolled back after exact cleanup inventories exist"
    end
  end
end
