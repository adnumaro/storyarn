defmodule Storyarn.Repo.Migrations.AddAccountReadOnlyState do
  use Ecto.Migration

  @moduledoc """
  Records when an account is over its plan's limits, and which plan it had
  over time.

  `subscriptions.read_only_reasons` lists the limits the account exceeds; while
  it is not empty, every workspace the account owns is read-only.

  `account_plan_periods` keeps the effective plan the account had from each
  `started_at` on, so a trashed item keeps the retention it was granted when it
  was deleted. Every account starts with one period holding its current
  effective plan.
  """

  def up do
    alter table(:subscriptions) do
      add :read_only_reasons, {:array, :string}, null: false, default: []
      add :read_only_since, :utc_datetime
    end

    create table(:account_plan_periods) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan, :string, null: false
      add :started_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:account_plan_periods, [:user_id, :started_at])

    execute("""
    INSERT INTO account_plan_periods (user_id, plan, started_at, inserted_at)
    SELECT user_id,
           CASE WHEN status IN ('active', 'trialing', 'past_due') THEN plan ELSE 'free' END,
           '1970-01-01 00:00:00',
           now()
    FROM subscriptions
    """)
  end

  def down do
    drop table(:account_plan_periods)

    alter table(:subscriptions) do
      remove :read_only_since
      remove :read_only_reasons
    end
  end
end
