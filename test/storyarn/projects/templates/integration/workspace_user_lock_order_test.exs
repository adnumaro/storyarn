defmodule Storyarn.Projects.ProjectTemplates.WorkspaceUserLockOrderTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oban.Job
  alias Storyarn.Accounts.User
  alias Storyarn.AccountsFixtures
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.ProjectTemplates
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplate
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.ProjectsFixtures
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.WorkspacesFixtures

  @timeout 30_000
  @blocked_timeout 15_000

  test "publication finalization locks the workspace before the requester" do
    Sandbox.unboxed_run(Repo, fn ->
      requester = unique_user("publication-lock-order")
      workspace = WorkspacesFixtures.workspace_fixture(requester)
      project = ProjectsFixtures.project_fixture(requester, %{workspace: workspace, name: "Publication Lock Order"})
      scope = AccountsFixtures.user_scope_fixture(requester)
      parent = self()

      try do
        assert {:ok, publication} =
                 ProjectTemplates.request_template_publication(scope, project, %{
                   name: "Publication Lock Order Template"
                 })

        publication_id = publication.id

        result =
          assert_workspace_before_user(workspace.id, requester.id, fn ->
            ProjectTemplates.perform_template_publication(publication.id,
              before_finalize: fn %{artifact: artifact} ->
                send(
                  parent,
                  {:publication_artifacts, publication.id, [artifact.snapshot_key, artifact.asset_manifest_key]}
                )

                :ok
              end
            )
          end)

        assert {:ok, %ProjectTemplatePublication{status: "published"} = published} = result
        assert published.requested_by_id == requester.id
        assert_receive {:publication_artifacts, ^publication_id, artifact_keys}, @timeout

        assert Enum.sort(artifact_keys) ==
                 Enum.sort([published.snapshot_storage_key, published.asset_manifest_storage_key])
      after
        cleanup([requester.id], [workspace.id])
      end
    end)
  end

  test "portable import locks the target workspace before the source user" do
    Sandbox.unboxed_run(Repo, fn ->
      exporter = unique_user("portable-export-lock-order")
      exporter_workspace = WorkspacesFixtures.workspace_fixture(exporter)

      source_project =
        ProjectsFixtures.project_fixture(exporter, %{
          workspace: exporter_workspace,
          name: "Portable Lock Order Source"
        })

      importer = unique_user("portable-import-lock-order")
      importer_workspace = WorkspacesFixtures.workspace_fixture(importer)
      slug = "portable-lock-order-#{System.unique_integer([:positive])}"
      output_path = bundle_path()

      try do
        assert {:ok, _export} =
                 ProjectTemplates.export_portable_template(source_project.id, output_path,
                   name: "Portable Lock Order Template",
                   slug: slug
                 )

        result =
          assert_workspace_before_user(importer_workspace.id, importer.id, fn ->
            ProjectTemplates.import_portable_template(output_path,
              visibility: "private",
              owner_id: importer.id,
              verify_user_id: importer.id,
              verify_workspace_id: importer_workspace.id,
              name: "Portable Lock Order Template",
              slug: slug
            )
          end)

        assert {:ok, %ProjectTemplate{} = template} = result
        assert template.owner_id == importer.id
        assert template.source_project.workspace_id == importer_workspace.id
      after
        File.rm(output_path)

        cleanup(
          [exporter.id, importer.id],
          [exporter_workspace.id, importer_workspace.id]
        )
      end
    end)
  end

  defp assert_workspace_before_user(workspace_id, user_id, operation) do
    parent = self()
    barrier = make_ref()
    gate = start_workspace_gate(workspace_id, parent, barrier)

    try do
      assert_receive {^barrier, :workspace_locked, gate_task_pid, gate_backend_pid}, @timeout
      assert gate_task_pid == gate.pid

      worker = start_operation(operation, parent, barrier)

      try do
        assert_receive {^barrier, :operation_ready, worker_task_pid, worker_backend_pid}, @timeout
        assert worker_task_pid == worker.pid

        assert wait_until_blocked_by(worker_backend_pid, gate_backend_pid),
               "operation did not block behind the workspace lock"

        assert {:ok, :available} = acquire_user_update_lock_nowait(user_id)

        send(gate.pid, {barrier, :release_workspace})
        result = Task.await(worker, @timeout)
        assert {:ok, :released} = Task.await(gate, @timeout)
        result
      after
        send(gate.pid, {barrier, :release_workspace})
        finish_task(worker)
      end
    after
      send(gate.pid, {barrier, :release_workspace})
      finish_task(gate)
    end
  end

  defp start_workspace_gate(workspace_id, parent, barrier) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        run_workspace_gate(workspace_id, parent, barrier)
      end)
    end)
  end

  defp run_workspace_gate(workspace_id, parent, barrier) do
    [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows

    Repo.transaction(fn ->
      hold_workspace_gate(workspace_id, parent, barrier, backend_pid)
    end)
  end

  defp hold_workspace_gate(workspace_id, parent, barrier, backend_pid) do
    %{num_rows: 1} =
      Repo.query!(
        "SELECT id FROM workspaces WHERE id = $1 FOR UPDATE",
        [workspace_id]
      )

    send(parent, {barrier, :workspace_locked, self(), backend_pid})

    receive do
      {^barrier, :release_workspace} -> :released
    after
      @timeout -> exit(:workspace_gate_release_timeout)
    end
  end

  defp start_operation(operation, parent, barrier) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {barrier, :operation_ready, self(), backend_pid})
        operation.()
      end)
    end)
  end

  defp wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
  end

  defp do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline) do
    if backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(10)
        do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
      end
    end
  end

  defp backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) do
    case Repo.query!(
           """
           SELECT wait_event_type,
                  $2::integer = ANY(pg_blocking_pids(pid)) AS blocked_by_workspace_gate
           FROM pg_stat_activity
           WHERE pid = $1::integer
           """,
           [blocked_backend_pid, blocker_backend_pid]
         ).rows do
      [["Lock", true]] -> true
      _other -> false
    end
  end

  defp acquire_user_update_lock_nowait(user_id) do
    fn ->
      Sandbox.unboxed_run(Repo, fn ->
        try do
          Repo.transaction(fn ->
            %{num_rows: 1} =
              Repo.query!(
                "SELECT id FROM users WHERE id = $1 FOR UPDATE NOWAIT",
                [user_id]
              )

            :available
          end)
        rescue
          error in Postgrex.Error ->
            {:error, Map.get(error.postgres || %{}, :code)}
        end
      end)
    end
    |> Task.async()
    |> Task.await(@timeout)
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp unique_user(prefix) do
    AccountsFixtures.user_fixture(%{
      email: "#{prefix}-#{Ecto.UUID.generate()}@example.com"
    })
  end

  defp bundle_path do
    Path.join(
      System.tmp_dir!(),
      "storyarn-lock-order-#{System.unique_integer([:positive])}.tar.gz"
    )
  end

  defp cleanup(user_ids, workspace_ids) do
    template_ids =
      Repo.all(
        from template in ProjectTemplate,
          where: template.owner_id in ^user_ids,
          select: template.id
      )

    version_storage_keys =
      Repo.all(
        from version in ProjectTemplateVersion,
          where: version.project_template_id in ^template_ids,
          select: [version.snapshot_storage_key, version.asset_manifest_storage_key]
      )

    publication_cleanup =
      Repo.all(
        from publication in ProjectTemplatePublication,
          where: publication.owner_id in ^user_ids,
          select: {
            publication.snapshot_storage_key,
            publication.asset_manifest_storage_key,
            publication.oban_job_id
          }
      )

    publication_storage_keys =
      Enum.flat_map(publication_cleanup, fn {snapshot_key, manifest_key, _job_id} ->
        [snapshot_key, manifest_key]
      end)

    job_ids =
      publication_cleanup
      |> Enum.map(&elem(&1, 2))
      |> Enum.reject(&is_nil/1)

    if template_ids != [] do
      Repo.update_all(
        from(template in ProjectTemplate, where: template.id in ^template_ids),
        set: [current_version_id: nil]
      )

      Repo.delete_all(from template in ProjectTemplate, where: template.id in ^template_ids)
    end

    Repo.delete_all(from workspace in Workspace, where: workspace.id in ^workspace_ids)

    if job_ids != [] do
      Repo.delete_all(from job in Job, where: job.id in ^job_ids)
    end

    Repo.delete_all(from user in User, where: user.id in ^user_ids)

    (List.flatten(version_storage_keys) ++ publication_storage_keys)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&Assets.storage_delete/1)
  end
end
