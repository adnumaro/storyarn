defmodule Storyarn.Flows.NamedVersionLimitConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.SnapshotStorage
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces.Workspace

  setup do
    fixtures =
      Sandbox.unboxed_run(Repo, fn ->
        user = user_fixture(%{email: "flow-version-limit-#{Ecto.UUID.generate()}@example.com"})
        project = project_fixture(user)
        flow = flow_fixture(project)

        for version_number <- 1..9 do
          insert_version!(flow, version_number, %{
            title: "Checkpoint #{version_number}"
          })
        end

        automatic_versions = [
          insert_version!(flow, 10, %{is_auto: true}),
          insert_version!(flow, 11, %{is_auto: true})
        ]

        %{
          user: user,
          project: project,
          flow: flow,
          automatic_versions: automatic_versions
        }
      end)

    on_exit(fn -> cleanup_fixtures(fixtures) end)
    fixtures
  end

  test "concurrent promotions consume the final named-version slot atomically", %{
    project: project,
    automatic_versions: automatic_versions
  } do
    results =
      run_concurrently(automatic_versions, fn version ->
        Sandbox.unboxed_run(Repo, fn ->
          Flows.update_version(version, %{title: "Promoted #{version.version_number}"})
        end)
      end)

    assert Enum.count(results, &match?({:ok, %EntityVersionRecord{}}, &1)) == 1

    assert Enum.count(results, fn
             {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} ->
               true

             _result ->
               false
           end) == 1

    persisted =
      Sandbox.unboxed_run(Repo, fn ->
        ids = Enum.map(automatic_versions, & &1.id)

        Repo.all(
          from(version in EntityVersionRecord,
            where: version.id in ^ids,
            order_by: [asc: version.version_number]
          )
        )
      end)

    assert Enum.count(persisted, &(not &1.is_auto and not is_nil(&1.title))) == 1
    assert Enum.count(persisted, &(&1.is_auto and is_nil(&1.title))) == 1

    assert Sandbox.unboxed_run(Repo, fn -> named_version_count(project.id) end) == 10
  end

  test "concurrent automatic checks create exactly one version after the interval", %{
    user: user,
    flow: flow,
    automatic_versions: automatic_versions
  } do
    latest = List.last(automatic_versions)
    expired_at = DateTime.add(TimeHelpers.now(), -601, :second)

    Sandbox.unboxed_run(Repo, fn ->
      Repo.update_all(
        from(version in EntityVersionRecord, where: version.id == ^latest.id),
        set: [inserted_at: expired_at]
      )
    end)

    results =
      run_concurrently([:first, :second], fn _attempt ->
        Sandbox.unboxed_run(Repo, fn ->
          Flows.maybe_create_version(flow, user.id,
            min_interval: 600,
            skip_diff: true
          )
        end)
      end)

    assert Enum.count(results, &match?({:ok, %EntityVersionRecord{is_auto: true}}, &1)) == 1
    assert Enum.count(results, &match?({:skipped, :too_recent}, &1)) == 1

    successful =
      Enum.find_value(results, fn
        {:ok, version} -> version
        _result -> nil
      end)

    latest = Sandbox.unboxed_run(Repo, fn -> Flows.get_latest_version(flow.id) end)

    assert latest.id == successful.id
    assert latest.version_number == 12
    assert latest.is_auto
    assert Sandbox.unboxed_run(Repo, fn -> Flows.count_versions(flow.id) end) == 12
  end

  defp run_concurrently(values, fun) do
    parent = self()

    tasks =
      Enum.map(values, fn value ->
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> fun.(value)
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end)

    pids =
      for _value <- values do
        assert_receive {:ready, pid}, 5_000
        pid
      end

    Enum.each(pids, &send(&1, :go))
    Enum.map(tasks, &Task.await(&1, 15_000))
  end

  defp insert_version!(flow, version_number, attrs) do
    base_attrs = %{
      entity_type: "flow",
      entity_id: flow.id,
      project_id: flow.project_id,
      version_number: version_number,
      title: nil,
      storage_key: "projects/#{flow.project_id}/snapshots/flow/#{flow.id}/test-#{version_number}.json.gz",
      snapshot_size_bytes: 0,
      checksum: String.duplicate("b", 64),
      is_auto: false
    }

    %EntityVersionRecord{}
    |> EntityVersionRecord.create_changeset(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp named_version_count(project_id) do
    Repo.aggregate(
      from(version in EntityVersionRecord,
        where:
          version.project_id == ^project_id and not is_nil(version.title) and
            version.is_auto == false
      ),
      :count
    )
  end

  defp cleanup_fixtures(%{user: user, project: project}) do
    Sandbox.unboxed_run(Repo, fn ->
      storage_keys =
        Repo.all(
          from(version in EntityVersionRecord,
            where: version.project_id == ^project.id,
            select: version.storage_key
          )
        )

      Repo.delete_all(from(version in EntityVersionRecord, where: version.project_id == ^project.id))
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))

      Enum.each(storage_keys, fn storage_key ->
        _cleanup_result = SnapshotStorage.delete(storage_key)
      end)
    end)
  end
end
