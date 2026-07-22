defmodule Storyarn.Repo.Migrations.HardenAiManagedInvariants do
  use Ecto.Migration

  def up do
    create index(:ai_allowance_reservations, [:status, :inserted_at])

    create index(:ai_provider_budget_reservations, [:currency, :inserted_at])

    create index(
             :ai_provider_budget_reservations,
             [:currency, :workspace_id_snapshot, :inserted_at]
           )

    alter table(:ai_operator_alerts) do
      modify :workspace_id_snapshot, :bigint, null: false
    end

    create constraint(
             :ai_allowance_reservations,
             :ai_allowance_reservations_settlement_complete,
             check:
               "(status = 'reserved' AND settled_at IS NULL) OR " <>
                 "(status IN ('committed', 'released') AND settled_at IS NOT NULL)"
           )

    create constraint(
             :ai_provider_budget_reservations,
             :ai_provider_budget_reservations_settlement_complete,
             check:
               "(status = 'reserved' AND actual_cost IS NULL AND settled_at IS NULL) OR " <>
                 "(status = 'settled' AND actual_cost IS NOT NULL AND settled_at IS NOT NULL)"
           )
  end

  def down do
    drop constraint(
           :ai_provider_budget_reservations,
           :ai_provider_budget_reservations_settlement_complete
         )

    drop constraint(
           :ai_allowance_reservations,
           :ai_allowance_reservations_settlement_complete
         )

    alter table(:ai_operator_alerts) do
      modify :workspace_id_snapshot, :bigint, null: true
    end

    drop index(
           :ai_provider_budget_reservations,
           [:currency, :workspace_id_snapshot, :inserted_at]
         )

    drop index(:ai_provider_budget_reservations, [:currency, :inserted_at])
    drop index(:ai_allowance_reservations, [:status, :inserted_at])
  end
end
