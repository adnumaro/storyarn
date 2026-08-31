defmodule Storyarn.AI.Integrations.Commands.WorkspaceAccessLocksTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI.Integrations.Commands.WorkspaceAccessLocks

  @outside_pg_bigint 9_223_372_036_854_775_808

  test "lock/2 rejects IDs outside PostgreSQL bigint with the public unavailable error" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    assert {:error, :workspace_unavailable} =
             WorkspaceAccessLocks.lock(%{user: %{id: owner.id}}, @outside_pg_bigint)

    assert {:error, :workspace_unavailable} =
             WorkspaceAccessLocks.lock(%{user: %{id: @outside_pg_bigint}}, workspace.id)
  end
end
