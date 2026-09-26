defmodule Storyarn.Repo.Migrations.MoveSubscriptionsToAccountsMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.MoveSubscriptionsToAccounts

  @migration_version 20_260_926_100_000

  if !Code.ensure_loaded?(MoveSubscriptionsToAccounts) do
    Code.require_file(
      Path.expand("../../../../priv/repo/migrations/20260926100000_move_subscriptions_to_accounts.exs", __DIR__)
    )
  end

  setup do
    prefix = "move_subscriptions_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_pre_migration_tables!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    seed!(prefix)
    %{prefix: prefix}
  end

  test "up keeps one subscription per account, preferring the one that still grants its plan", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    # The owner of two workspaces keeps the active Beta, not the older canceled
    # Pro; an account without a workspace gets the default plan.
    assert account_subscriptions(prefix) == [
             {1001, "beta", "active"},
             {1002, "free", "active"},
             {1003, "free", "active"}
           ]

    refute column?(prefix, "workspace_id")
    assert index?(prefix, "subscriptions_user_id_index")

    assert_raise Postgrex.Error, ~r/not_null_violation|null value in column "user_id"/, fn ->
      Repo.query!(
        "INSERT INTO #{prefix}.subscriptions (plan, status, inserted_at, updated_at) VALUES ('free', 'active', now(), now())"
      )
    end
  end

  test "down gives every workspace its owner's subscription and up applies again", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert :ok = run_migration(:down, prefix)

    assert workspace_subscriptions(prefix) == [
             {2001, "beta", "active"},
             {2002, "beta", "active"},
             {2003, "free", "active"}
           ]

    refute column?(prefix, "user_id")
    assert index?(prefix, "subscriptions_workspace_id_index")

    assert :ok = run_migration(:up, prefix)

    assert account_subscriptions(prefix) == [
             {1001, "beta", "active"},
             {1002, "free", "active"},
             {1003, "free", "active"}
           ]
  end

  defp create_pre_migration_tables!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.users (
      id bigserial PRIMARY KEY,
      email text NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.workspaces (
      id bigserial PRIMARY KEY,
      owner_id bigint NOT NULL REFERENCES #{prefix}.users(id),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.subscriptions (
      id bigserial PRIMARY KEY,
      workspace_id bigint NOT NULL REFERENCES #{prefix}.workspaces(id) ON DELETE CASCADE,
      plan varchar(255) NOT NULL DEFAULT 'free',
      status varchar(255) NOT NULL DEFAULT 'active',
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
    )
    """)

    Repo.query!("CREATE UNIQUE INDEX subscriptions_workspace_id_index ON #{prefix}.subscriptions (workspace_id)")
  end

  # 1001 owns two workspaces: an old canceled Pro and a newer active Beta.
  # 1002 owns one Free workspace. 1003 owns nothing and has no subscription.
  defp seed!(prefix) do
    Repo.query!("""
    INSERT INTO #{prefix}.users (id, email, inserted_at, updated_at) VALUES
      (1001, 'owner@example.com', now(), now()),
      (1002, 'free@example.com', now(), now()),
      (1003, 'no-workspace@example.com', now(), now())
    """)

    Repo.query!("""
    INSERT INTO #{prefix}.workspaces (id, owner_id, inserted_at, updated_at) VALUES
      (2001, 1001, now(), now()),
      (2002, 1001, now(), now()),
      (2003, 1002, now(), now())
    """)

    Repo.query!("""
    INSERT INTO #{prefix}.subscriptions (id, workspace_id, plan, status, inserted_at, updated_at) VALUES
      (3001, 2001, 'pro', 'canceled', now() - interval '30 days', now() - interval '30 days'),
      (3002, 2002, 'beta', 'active', now() - interval '1 day', now() - interval '1 day'),
      (3003, 2003, 'free', 'active', now(), now())
    """)
  end

  defp account_subscriptions(prefix) do
    Enum.map(
      Repo.query!("SELECT user_id, plan, status FROM #{prefix}.subscriptions ORDER BY user_id").rows,
      &List.to_tuple/1
    )
  end

  defp workspace_subscriptions(prefix) do
    Enum.map(
      Repo.query!("SELECT workspace_id, plan, status FROM #{prefix}.subscriptions ORDER BY workspace_id").rows,
      &List.to_tuple/1
    )
  end

  defp column?(prefix, column) do
    Repo.query!(
      "SELECT 1 FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'subscriptions' AND column_name = $2",
      [prefix, column]
    ).num_rows == 1
  end

  defp index?(prefix, index) do
    Repo.query!("SELECT 1 FROM pg_indexes WHERE schemaname = $1 AND indexname = $2", [prefix, index]).num_rows == 1
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      MoveSubscriptionsToAccounts,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end
end
