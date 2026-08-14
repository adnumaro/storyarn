defmodule Storyarn.Repo.Migrations.AddProjectSnapshotRestoreContractVersion do
  use Ecto.Migration

  @version_constraint :project_snapshots_restore_contract_version
  @capture_constraint :project_snapshots_restore_contract_capture
  @guard_function :storyarn_guard_project_snapshot_restore_contract
  @guard_trigger :project_snapshots_restore_contract_immutable

  def up do
    alter table(:project_snapshots) do
      add :restore_contract_version, :integer
    end

    create constraint(:project_snapshots, @version_constraint,
             check: "restore_contract_version IS NULL OR restore_contract_version = 1"
           )

    create constraint(:project_snapshots, @capture_constraint,
             check:
               "restore_contract_version IS NULL OR " <>
                 "(capture_digest IS NOT NULL AND captured_at IS NOT NULL)"
           )

    execute("""
    CREATE FUNCTION #{@guard_function}()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.restore_contract_version IS DISTINCT FROM OLD.restore_contract_version AND NOT (
        OLD.restore_contract_version IS NULL AND
        NEW.restore_contract_version = 1 AND
        OLD.format_version = 2 AND NEW.format_version = 2 AND
        OLD.lifecycle_state = 'pending' AND NEW.lifecycle_state = 'pending' AND
        OLD.capture_digest IS NULL AND OLD.captured_at IS NULL AND
        NEW.capture_digest IS NOT NULL AND NEW.captured_at IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'project snapshot restore contract is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER #{@guard_trigger}
    BEFORE UPDATE OF restore_contract_version ON project_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION #{@guard_function}()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS #{@guard_trigger} ON project_snapshots")
    execute("DROP FUNCTION IF EXISTS #{@guard_function}()")

    drop constraint(:project_snapshots, @capture_constraint)
    drop constraint(:project_snapshots, @version_constraint)

    alter table(:project_snapshots) do
      remove :restore_contract_version
    end
  end
end
