defmodule Storyarn.Repo.Migrations.CreateAiManagedAllowance do
  use Ecto.Migration

  def up do
    alter table(:ai_route_options) do
      add :price_units, :bigint, null: false, default: 1
      add :provider_configuration, :map, null: false, default: %{}
    end

    execute "ALTER TABLE ai_route_options ALTER COLUMN price_units DROP DEFAULT"
    execute "ALTER TABLE ai_route_options ALTER COLUMN provider_configuration DROP DEFAULT"

    create constraint(:ai_route_options, :ai_route_options_price_units_positive,
             check: "price_units > 0"
           )

    create table(:ai_allowance_accounts) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      add :available_units, :bigint, null: false, default: 0
      add :reserved_units, :bigint, null: false, default: 0
      add :committed_units, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_allowance_accounts, [:workspace_id])

    create constraint(:ai_allowance_accounts, :ai_allowance_accounts_status,
             check: "status IN ('active', 'paused')"
           )

    create constraint(:ai_allowance_accounts, :ai_allowance_accounts_nonnegative,
             check: "available_units >= 0 AND reserved_units >= 0 AND committed_units >= 0"
           )

    create table(:ai_allowance_grants) do
      add :account_id, references(:ai_allowance_accounts, on_delete: :nilify_all)
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint, null: false
      add :grant_key, :string, null: false
      add :kind, :string, null: false
      add :units, :bigint, null: false
      add :remaining_units, :bigint, null: false
      add :expires_at, :utc_datetime
      add :granted_by_id, references(:users, on_delete: :nilify_all)
      add :actor_id, :bigint
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_allowance_grants, [:workspace_id_snapshot, :grant_key])
    create index(:ai_allowance_grants, [:account_id, :expires_at])

    create constraint(:ai_allowance_grants, :ai_allowance_grants_kind,
             check: "kind IN ('one_time', 'periodic', 'adjustment')"
           )

    create constraint(:ai_allowance_grants, :ai_allowance_grants_units,
             check: "units > 0 AND remaining_units >= 0 AND remaining_units <= units"
           )

    create table(:ai_allowance_reservations) do
      add :operation_id, references(:ai_operations, on_delete: :restrict), null: false
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint, null: false
      add :price_id, :string, null: false
      add :price_version, :integer, null: false
      add :units, :bigint, null: false
      add :status, :string, null: false
      add :settled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_allowance_reservations, [:operation_id])
    create index(:ai_allowance_reservations, [:workspace_id_snapshot, :status])

    create constraint(:ai_allowance_reservations, :ai_allowance_reservations_status,
             check: "status IN ('reserved', 'committed', 'released')"
           )

    create constraint(:ai_allowance_reservations, :ai_allowance_reservations_units,
             check: "units > 0 AND price_version > 0"
           )

    create table(:ai_allowance_allocations) do
      add :reservation_id, references(:ai_allowance_reservations, on_delete: :restrict),
        null: false

      add :grant_id, references(:ai_allowance_grants, on_delete: :restrict), null: false
      add :units, :bigint, null: false
      add :restored_units, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:ai_allowance_allocations, [:reservation_id, :grant_id])

    create constraint(:ai_allowance_allocations, :ai_allowance_allocations_units,
             check: "units > 0 AND restored_units >= 0 AND restored_units <= units"
           )

    create table(:ai_allowance_ledger_entries) do
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint, null: false
      add :operation_id, references(:ai_operations, on_delete: :restrict)
      add :grant_id, references(:ai_allowance_grants, on_delete: :restrict)
      add :reservation_id, references(:ai_allowance_reservations, on_delete: :restrict)
      add :kind, :string, null: false
      add :units, :bigint, null: false
      add :available_delta, :bigint, null: false
      add :idempotency_key, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:ai_allowance_ledger_entries, [:workspace_id_snapshot, :idempotency_key],
             name: :ai_allowance_ledger_workspace_idempotency_unique
           )

    create index(:ai_allowance_ledger_entries, [:workspace_id_snapshot, :inserted_at])
    create index(:ai_allowance_ledger_entries, [:operation_id])

    create constraint(:ai_allowance_ledger_entries, :ai_allowance_ledger_entries_kind,
             check: "kind IN ('grant', 'reserve', 'commit', 'release', 'adjustment', 'expiry')"
           )

    create constraint(:ai_allowance_ledger_entries, :ai_allowance_ledger_entries_units,
             check: "units > 0"
           )

    create table(:ai_provider_budget_reservations) do
      add :operation_id, references(:ai_operations, on_delete: :restrict), null: false
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint, null: false
      add :provider, :string, null: false
      add :model, :string, null: false
      add :price_snapshot, :map, null: false
      add :estimated_cost, :decimal, null: false
      add :actual_cost, :decimal
      add :currency, :string, null: false
      add :status, :string, null: false
      add :settled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_provider_budget_reservations, [:operation_id])
    create index(:ai_provider_budget_reservations, [:provider, :inserted_at])
    create index(:ai_provider_budget_reservations, [:workspace_id_snapshot, :inserted_at])

    create constraint(:ai_provider_budget_reservations, :ai_provider_budget_reservations_status,
             check: "status IN ('reserved', 'settled')"
           )

    create constraint(:ai_provider_budget_reservations, :ai_provider_budget_reservations_cost,
             check:
               "estimated_cost >= 0 AND (actual_cost IS NULL OR actual_cost >= 0) AND " <>
                 "char_length(currency) BETWEEN 1 AND 12"
           )

    create table(:ai_operator_alerts) do
      add :dedupe_key, :string, null: false
      add :kind, :string, null: false
      add :severity, :string, null: false
      add :status, :string, null: false, default: "open"
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint
      add :operation_id, references(:ai_operations, on_delete: :restrict)
      add :metadata, :map, null: false, default: %{}
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_operator_alerts, [:dedupe_key])
    create index(:ai_operator_alerts, [:status, :inserted_at])

    create constraint(:ai_operator_alerts, :ai_operator_alerts_kind,
             check:
               "kind IN ('allowance_anomaly', 'provider_cost_spike', 'unknown_operation', " <>
                 "'stale_reservation', 'duplicate_attempt')"
           )

    create constraint(:ai_operator_alerts, :ai_operator_alerts_severity,
             check: "severity IN ('warning', 'critical')"
           )

    create constraint(:ai_operator_alerts, :ai_operator_alerts_status,
             check: "status IN ('open', 'resolved')"
           )

    execute_append_only_ledger()
  end

  def down do
    execute "DROP TRIGGER IF EXISTS ai_allowance_ledger_entries_append_only_trigger ON ai_allowance_ledger_entries;"
    execute "DROP FUNCTION IF EXISTS ai_allowance_ledger_entries_append_only();"

    drop table(:ai_operator_alerts)
    drop table(:ai_provider_budget_reservations)
    drop table(:ai_allowance_ledger_entries)
    drop table(:ai_allowance_allocations)
    drop table(:ai_allowance_reservations)
    drop table(:ai_allowance_grants)
    drop table(:ai_allowance_accounts)

    drop constraint(:ai_route_options, :ai_route_options_price_units_positive)

    alter table(:ai_route_options) do
      remove :provider_configuration
      remove :price_units
    end
  end

  defp execute_append_only_ledger do
    execute """
    CREATE FUNCTION ai_allowance_ledger_entries_append_only() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'ai_allowance_ledger_entries is append-only (DELETE blocked)';
      END IF;

      IF pg_trigger_depth() > 1
         AND OLD.workspace_id IS NOT NULL
         AND NEW.workspace_id IS NULL
         AND NEW.workspace_id_snapshot = OLD.workspace_id_snapshot
         AND NEW.operation_id IS NOT DISTINCT FROM OLD.operation_id
         AND NEW.grant_id IS NOT DISTINCT FROM OLD.grant_id
         AND NEW.reservation_id IS NOT DISTINCT FROM OLD.reservation_id
         AND NEW.kind = OLD.kind
         AND NEW.units = OLD.units
         AND NEW.available_delta = OLD.available_delta
         AND NEW.idempotency_key = OLD.idempotency_key
         AND NEW.metadata = OLD.metadata
         AND NEW.inserted_at = OLD.inserted_at THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'ai_allowance_ledger_entries is append-only (UPDATE blocked)';
    END;
    $$ LANGUAGE plpgsql;

    """

    execute """
    CREATE TRIGGER ai_allowance_ledger_entries_append_only_trigger
    BEFORE UPDATE OR DELETE ON ai_allowance_ledger_entries
    FOR EACH ROW EXECUTE FUNCTION ai_allowance_ledger_entries_append_only();
    """
  end
end
