defmodule Storyarn.Repo.Migrations.MoveSubscriptionsToAccounts do
  use Ecto.Migration

  @moduledoc """
  Moves subscriptions from workspaces to the accounts that own them.

  Each account keeps one subscription. When an owner had several, the one on a
  plan other than the default wins, then the oldest. Accounts without any
  subscription get the default one. Workspaces take their limits from their
  owner's subscription from now on.
  """

  def up do
    alter table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    execute("""
    UPDATE subscriptions AS subscription
    SET user_id = workspace.owner_id
    FROM workspaces AS workspace
    WHERE workspace.id = subscription.workspace_id
    """)

    execute("""
    DELETE FROM subscriptions
    WHERE id IN (
      SELECT id
      FROM (
        SELECT id,
               row_number() OVER (
                 PARTITION BY user_id
                 ORDER BY (plan <> 'free') DESC, id
               ) AS position
        FROM subscriptions
      ) AS ranked
      WHERE ranked.position > 1
    )
    """)

    execute("""
    INSERT INTO subscriptions (user_id, plan, status, inserted_at, updated_at)
    SELECT account.id, 'free', 'active', now(), now()
    FROM users AS account
    WHERE NOT EXISTS (
      SELECT 1 FROM subscriptions AS subscription WHERE subscription.user_id = account.id
    )
    """)

    drop unique_index(:subscriptions, [:workspace_id])

    alter table(:subscriptions) do
      modify :user_id, :bigint, null: false
      remove :workspace_id
    end

    create unique_index(:subscriptions, [:user_id])
  end

  def down do
    drop unique_index(:subscriptions, [:user_id])

    alter table(:subscriptions) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    execute("""
    INSERT INTO subscriptions (workspace_id, plan, status, inserted_at, updated_at)
    SELECT workspace.id, subscription.plan, subscription.status, now(), now()
    FROM workspaces AS workspace
    JOIN subscriptions AS subscription ON subscription.user_id = workspace.owner_id
    """)

    execute("DELETE FROM subscriptions WHERE workspace_id IS NULL")

    alter table(:subscriptions) do
      modify :workspace_id, :bigint, null: false
      remove :user_id
    end

    create unique_index(:subscriptions, [:workspace_id])
  end
end
