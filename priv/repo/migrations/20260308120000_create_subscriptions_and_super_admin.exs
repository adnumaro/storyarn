defmodule Storyarn.Repo.Migrations.CreateSubscriptionsAndSuperAdmin do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :plan, :string, null: false, default: "free"
      add :status, :string, null: false, default: "active"
      add :payment_provider, :string
      add :external_customer_id, :string
      add :external_subscription_id, :string
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :canceled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:workspace_id])
    create index(:subscriptions, [:external_customer_id])
    create index(:subscriptions, [:external_subscription_id])

    alter table(:users) do
      add :is_super_admin, :boolean, default: false, null: false
    end

    # Data migration: free subscription for all existing workspaces
    execute(
      """
      INSERT INTO subscriptions (workspace_id, plan, status, inserted_at, updated_at)
      SELECT id, 'free', 'active', NOW(), NOW() FROM workspaces
      """,
      """
      DELETE FROM subscriptions
      """
    )
  end
end
