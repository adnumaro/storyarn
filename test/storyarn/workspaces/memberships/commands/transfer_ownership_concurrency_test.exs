defmodule Storyarn.Workspaces.Memberships.Commands.TransferOwnershipConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Lifecycle
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  test "two concurrent transfers of one workspace converge on exactly one owner" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      first_receiver = user_without_workspace()
      second_receiver = user_without_workspace()
      _first_membership = workspace_membership_fixture(workspace, first_receiver, "member")
      _second_membership = workspace_membership_fixture(workspace, second_receiver, "viewer")

      try do
        tasks =
          run_concurrently([
            fn -> Memberships.transfer_owner(Scope.for_user(owner), workspace.id, first_receiver.id) end,
            fn -> Memberships.transfer_owner(Scope.for_user(owner), workspace.id, second_receiver.id) end
          ])

        results = Task.await_many(tasks, 5_000)

        assert Enum.count(results, &match?({:ok, %{changed?: true}}, &1)) == 1
        assert Enum.count(results, &match?({:error, :unauthorized}, &1)) == 1

        persisted_workspace = Repo.get!(Workspace, workspace.id)
        memberships = Memberships.list_workspace_members(workspace.id)
        owners = Enum.filter(memberships, &(&1.role == "owner"))

        assert [%{user_id: owner_id}] = owners
        assert owner_id == persisted_workspace.owner_id
      after
        cleanup([workspace.id], [owner.id, first_receiver.id, second_receiver.id])
      end
    end)
  end

  test "workspace creation and ownership receipt serialize the receiver's final slot" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      receiver = user_without_workspace()
      _receiver_membership = workspace_membership_fixture(workspace, receiver, "member")

      try do
        holder = hold_user_lock(receiver.id)
        assert_receive {:user_lock_held, holder_pid}, @timeout

        {transfer, transfer_pid, transfer_backend_pid} =
          start_observed_operation(self(), :transfer, fn ->
            Memberships.transfer_owner(Scope.for_user(owner), workspace.id, receiver.id)
          end)

        {creation, creation_pid, creation_backend_pid} =
          start_observed_operation(self(), :creation, fn ->
            Lifecycle.create_workspace(Scope.for_user(receiver), %{
              name: "Concurrent receiver workspace",
              slug: "concurrent-receiver-#{System.unique_integer([:positive])}"
            })
          end)

        send(transfer_pid, :start_operation)
        send(creation_pid, :start_operation)

        try do
          # The holder owns the only deliberately contended row: the receiver's User record.
          # Both operations must therefore reach and wait on that shared capacity lock.
          assert_connection_waiting_on_lock(transfer_backend_pid)
          assert_connection_waiting_on_lock(creation_backend_pid)
        after
          send(holder_pid, :release_user_lock)
        end

        assert {:ok, :ok} = Task.await(holder, @timeout)

        results = Task.await_many([transfer, creation], @timeout)

        assert Enum.count(results, &match?({:ok, _receipt_or_workspace}, &1)) == 1

        assert Enum.count(results, fn
                 {:error, :limit_reached, %{resource: :workspaces_per_user, used: 1, limit: 1}} -> true
                 _other -> false
               end) == 1

        assert Repo.aggregate(from(candidate in Workspace, where: candidate.owner_id == ^receiver.id), :count) == 1
      after
        cleanup_owned_by([owner.id, receiver.id])
        cleanup([], [owner.id, receiver.id])
      end
    end)
  end

  defp run_concurrently(operations) do
    parent = self()

    tasks =
      Enum.map(operations, fn operation ->
        Task.async(fn -> run_unboxed_operation(parent, operation) end)
      end)

    ready_pids =
      Enum.map(tasks, fn _task ->
        assert_receive {:operation_ready, task_pid}, 1_000
        task_pid
      end)

    Enum.each(ready_pids, &send(&1, :start_operation))
    tasks
  end

  defp run_unboxed_operation(parent, operation) do
    Sandbox.unboxed_run(Repo, fn ->
      send(parent, {:operation_ready, self()})

      receive do
        :start_operation -> operation.()
      end
    end)
  end

  defp start_observed_operation(parent, label, operation) do
    task =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {:observed_operation_ready, label, self(), backend_pid})

          receive do
            :start_operation -> operation.()
          end
        end)
      end)

    assert_receive {:observed_operation_ready, ^label, task_pid, backend_pid}, @timeout
    {task, task_pid, backend_pid}
  end

  defp hold_user_lock(user_id) do
    parent = self()

    Task.async(fn -> hold_user_lock_unboxed(parent, user_id) end)
  end

  defp hold_user_lock_unboxed(parent, user_id) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transact(fn ->
        Repo.one!(from(user in User, where: user.id == ^user_id, lock: "FOR UPDATE"))
        send(parent, {:user_lock_held, self()})

        receive do
          :release_user_lock -> {:ok, :ok}
        end
      end)
    end)
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts \\ 100)

  defp assert_connection_waiting_on_lock(_backend_pid, 0) do
    flunk("operation did not block on the receiver user lock")
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts) do
    if Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid]).rows ==
         [["Lock"]] do
      :ok
    else
      Process.sleep(10)
      assert_connection_waiting_on_lock(backend_pid, attempts - 1)
    end
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end

  defp cleanup_owned_by(user_ids) do
    Repo.delete_all(from(workspace in Workspace, where: workspace.owner_id in ^user_ids))
  end

  defp cleanup(workspace_ids, user_ids) do
    if workspace_ids != [] do
      Repo.delete_all(from(workspace in Workspace, where: workspace.id in ^workspace_ids))
    end

    Repo.delete_all(from(user in User, where: user.id in ^user_ids))
  end
end
