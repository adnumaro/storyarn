defmodule Storyarn.Workspaces.Lifecycle.Commands.OwnerMutationTransferConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.AI
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.AI.WorkspacePolicyAudit
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Memberships.Commands.TransferOwnership
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @timeout 10_000

  test "owner-only mutations wait for a transfer and reauthorize the former owner" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      owner_scope = Scope.for_user(owner)
      workspace = workspace_fixture(owner)
      receiver = user_without_workspace()
      _receiver_membership = workspace_membership_fixture(workspace, receiver, "member")

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn -> cleanup(workspace.id, [owner.id, receiver.id]) end)
      end)

      parent = self()
      barrier = make_ref()
      transfer = paused_transfer(parent, barrier, owner_scope, workspace.id, receiver.id)

      assert_receive {^barrier, :transfer_paused, transfer_pid}, @timeout

      mutations = [
        concurrent_mutation(parent, barrier, :update, fn ->
          Workspaces.update_workspace(owner_scope, workspace.id, %{name: "Unauthorized rename"})
        end),
        concurrent_mutation(parent, barrier, :delete, fn ->
          Workspaces.delete_workspace(owner_scope, workspace.id)
        end),
        concurrent_mutation(parent, barrier, :ai_policy, fn ->
          AI.update_workspace_policy(owner_scope, workspace.id, [])
        end)
      ]

      contenders = await_mutation_readiness(barrier, mutations)
      Enum.each(contenders, fn {_name, task_pid, _backend_pid} -> send(task_pid, {barrier, :start}) end)

      assert_connections_waiting_on_lock(Enum.map(contenders, &elem(&1, 2)))
      refute_receive {^barrier, :mutation_finished, _name, _result}, 50

      send(transfer_pid, {barrier, :finish_transfer})

      assert {:ok, %{changed?: true, new_owner_id: receiver_id}} = Task.await(transfer, @timeout)
      assert receiver_id == receiver.id

      assert [
               {:error, :unauthorized},
               {:error, :unauthorized},
               {:error, :unauthorized}
             ] = Task.await_many(mutations, @timeout)

      persisted_workspace = Repo.get!(Workspace, workspace.id)
      assert persisted_workspace.owner_id == receiver.id
      assert persisted_workspace.name == workspace.name

      assert %{role: "admin"} =
               Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id, user_id: owner.id)

      assert %{role: "owner"} =
               Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id, user_id: receiver.id)

      refute Repo.get_by(WorkspacePolicy, workspace_id: workspace.id)

      assert Repo.aggregate(
               from(audit in WorkspacePolicyAudit,
                 where: audit.workspace_id_snapshot == ^workspace.id
               ),
               :count
             ) == 0
    end)
  end

  defp paused_transfer(parent, barrier, owner_scope, workspace_id, receiver_id) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        TransferOwnership.transfer(owner_scope, workspace_id, receiver_id,
          after_owner_demotion: fn ->
            send(parent, {barrier, :transfer_paused, self()})

            receive do
              {^barrier, :finish_transfer} -> :ok
            after
              @timeout -> {:error, :transfer_pause_timeout}
            end
          end
        )
      end)
    end)
  end

  defp concurrent_mutation(parent, barrier, name, mutation) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {barrier, :mutation_ready, name, self(), backend_pid})

        receive do
          {^barrier, :start} -> :ok
        after
          @timeout -> raise "mutation start timeout"
        end

        result = mutation.()
        send(parent, {barrier, :mutation_finished, name, result})
        result
      end)
    end)
  end

  defp await_mutation_readiness(barrier, mutations) do
    Enum.map(mutations, fn _mutation ->
      assert_receive {^barrier, :mutation_ready, name, task_pid, backend_pid}, @timeout
      {name, task_pid, backend_pid}
    end)
  end

  defp assert_connections_waiting_on_lock(backend_pids, attempts \\ 100)

  defp assert_connections_waiting_on_lock(_backend_pids, 0) do
    flunk("owner-only mutations did not block on the workspace lock")
  end

  defp assert_connections_waiting_on_lock(backend_pids, attempts) do
    all_waiting? =
      Enum.all?(backend_pids, fn backend_pid ->
        Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid]).rows ==
          [["Lock"]]
      end)

    if all_waiting? do
      :ok
    else
      Process.sleep(10)
      assert_connections_waiting_on_lock(backend_pids, attempts - 1)
    end
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end

  defp cleanup(workspace_id, user_ids) do
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id in ^user_ids))
  end
end
