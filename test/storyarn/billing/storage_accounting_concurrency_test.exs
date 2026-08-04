defmodule Storyarn.Billing.StorageAccountingConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Workspaces.Workspace

  @checksum String.duplicate("a", 64)
  @timeout 10_000

  test "concurrent reservations cannot both consume the same workspace capacity" do
    %{user: user, project: project, snapshot: snapshot, workspace: workspace, limit: limit} =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "storage-reservation-race-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        workspace = Repo.get!(Workspace, project.workspace_id)
        limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)
        snapshot = insert_full_snapshot!(project)

        %Asset{}
        |> Ecto.Changeset.change(%{
          filename: "capacity.bin",
          content_type: "application/octet-stream",
          size: limit - snapshot.accounted_size_bytes - 100,
          key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/capacity.bin",
          project_id: project.id,
          uploaded_by_id: user.id
        })
        |> Repo.insert!()

        %{user: user, project: project, snapshot: snapshot, workspace: workspace, limit: limit}
      end)

    on_exit(fn -> cleanup_fixture(user, project, workspace) end)

    parent = self()
    barrier = make_ref()

    reserve = fn key ->
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          send(parent, {barrier, :ready, self()})

          receive do
            {^barrier, :reserve} ->
              Billing.reserve_storage(%{
                workspace_id: workspace.id,
                project_id: project.id,
                project_snapshot_id: snapshot.id,
                idempotency_key: key,
                kind: "restore_staging",
                reserved_bytes: 75
              })
          after
            @timeout -> exit(:reservation_barrier_timeout)
          end
        after
          Sandbox.checkin(Repo)
        end
      end)
    end

    first = reserve.("race:first")
    second = reserve.("race:second")

    assert_receive {^barrier, :ready, first_pid}, @timeout
    assert_receive {^barrier, :ready, second_pid}, @timeout

    send(first_pid, {barrier, :reserve})
    send(second_pid, {barrier, :reserve})

    results = [Task.await(first, @timeout), Task.await(second, @timeout)]

    assert Enum.count(results, &match?({:ok, %StorageReservation{}}, &1)) == 1

    assert Enum.count(
             results,
             &match?(
               {:error, :limit_reached, %{required: 75, available: 25, limit: ^limit}},
               &1
             )
           ) == 1

    usage = Sandbox.unboxed_run(Repo, fn -> Billing.workspace_storage_usage(workspace.id) end)
    assert usage.active_reservations.bytes == 75
    assert usage.accounted_bytes == limit - 25
  end

  test "concurrent build reservations cannot own the same snapshot target" do
    %{user: user, project: project, snapshot: snapshot, workspace: workspace} =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "storage-snapshot-operation-race-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        workspace = Repo.get!(Workspace, project.workspace_id)
        snapshot = insert_pending_snapshot!(project)

        %{user: user, project: project, snapshot: snapshot, workspace: workspace}
      end)

    on_exit(fn -> cleanup_fixture(user, project, workspace) end)

    parent = self()
    barrier = make_ref()

    reserve = fn key ->
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          send(parent, {barrier, :ready, self()})

          receive do
            {^barrier, :reserve} ->
              Billing.reserve_storage(%{
                workspace_id: workspace.id,
                project_id: project.id,
                project_snapshot_id: snapshot.id,
                idempotency_key: key,
                kind: "snapshot_build",
                reserved_bytes: 75
              })
          after
            @timeout -> exit(:reservation_barrier_timeout)
          end
        after
          Sandbox.checkin(Repo)
        end
      end)
    end

    first = reserve.("snapshot-race:first")
    second = reserve.("snapshot-race:second")

    assert_receive {^barrier, :ready, first_pid}, @timeout
    assert_receive {^barrier, :ready, second_pid}, @timeout

    send(first_pid, {barrier, :reserve})
    send(second_pid, {barrier, :reserve})

    results = [Task.await(first, @timeout), Task.await(second, @timeout)]

    assert Enum.count(results, &match?({:ok, %StorageReservation{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :storage_reservation_active_for_snapshot}, &1)) == 1

    active_count =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.aggregate(
          from(reservation in StorageReservation,
            where:
              reservation.project_snapshot_id_snapshot == ^snapshot.id and
                reservation.status == "active"
          ),
          :count
        )
      end)

    assert active_count == 1
  end

  defp insert_full_snapshot!(project) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/#{token}"

    %ProjectSnapshot{}
    |> ProjectSnapshot.object_set_changeset(%{
      project_id: project.id,
      version_number: 1,
      project_storage_key: prefix <> "/project.json",
      project_size_bytes: 10,
      project_checksum: @checksum,
      format_version: 1,
      object_prefix: prefix,
      manifest_storage_key: prefix <> "/manifest.json",
      manifest_size_bytes: 10,
      manifest_checksum: String.duplicate("b", 64),
      total_size_bytes: 30,
      object_count: 3,
      asset_count: 1,
      blob_count: 1
    })
    |> Repo.insert!()
  end

  defp insert_pending_snapshot!(project) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/#{token}"

    %ProjectSnapshot{}
    |> ProjectSnapshot.pending_object_set_changeset(%{
      project_id: project.id,
      version_number: 1,
      object_prefix: prefix,
      mode: "full"
    })
    |> Repo.insert!()
  end

  defp cleanup_fixture(user, project, workspace) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(
        from(reservation in StorageReservation,
          where: reservation.workspace_id_snapshot == ^workspace.id
        )
      )

      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(current in Workspace, where: current.id == ^workspace.id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
