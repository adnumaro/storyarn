defmodule Storyarn.Projects.Assets.Commands.AssetRegistrationConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "registration and variant linking serialize before family trash without deadlock" do
    %{project: project, user: user} = create_scenario()
    on_exit(fn -> cleanup_scenario(project, user) end)

    original =
      Sandbox.unboxed_run(Repo, fn ->
        register_asset!(project, user, "original.png", "original")
      end)

    parent = self()
    barrier = make_ref()

    gate = project_lock_gate(project.id, parent, barrier)
    assert_receive {^barrier, :project_locked}, @timeout

    registration =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :registration_ready, backend_pid})

          Repo.transact(fn ->
            variant_attrs =
              asset_attrs(project.id, "variant.webp", "variant", %{
                "is_variant" => true,
                "original_asset_id" => original.id
              })

            with {:ok, %{asset_id: variant_id}} <-
                   Projects.register_uploaded_asset(project.id, user.id, variant_attrs, :generic),
                 {:ok, receipt} <-
                   Projects.link_asset_variant(project.id, original.id, variant_id) do
              {:ok, %{receipt: receipt, variant_id: variant_id}}
            end
          end)
        after
          Sandbox.checkin(Repo)
        end
      end)

    assert_receive {^barrier, :registration_ready, registration_backend_pid}, @timeout
    assert wait_until_blocked(registration_backend_pid)

    trash =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :trash_ready, backend_pid})
          Projects.move_asset_to_trash(project.id, original.id, user.id)
        after
          Sandbox.checkin(Repo)
        end
      end)

    assert_receive {^barrier, :trash_ready, trash_backend_pid}, @timeout
    assert wait_until_blocked(trash_backend_pid)

    send(gate.pid, {barrier, :release_project})

    assert {:ok, :released} = Task.await(gate, @timeout)

    assert {:ok, %{receipt: %{asset_id: original_id}, variant_id: variant_id}} =
             Task.await(registration, @timeout)

    assert original_id == original.id
    assert {:ok, %Asset{id: ^original_id, deleted_at: %DateTime{}}} = Task.await(trash, @timeout)

    {persisted_original, persisted_variant} =
      Sandbox.unboxed_run(Repo, fn ->
        {Repo.get!(Asset, original_id), Repo.get!(Asset, variant_id)}
      end)

    assert persisted_original.deleted_at
    assert persisted_variant.deleted_at
    assert persisted_original.metadata["web_asset_id"] == variant_id
    assert persisted_variant.metadata["original_asset_id"] == original_id
  end

  defp project_lock_gate(project_id, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Repo.transaction(fn ->
          Repo.query!("SELECT id FROM projects WHERE id = $1 FOR UPDATE", [project_id])
          send(parent, {barrier, :project_locked})

          receive do
            {^barrier, :release_project} -> :released
          after
            @timeout -> exit(:project_gate_release_timeout)
          end
        end)
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_until_blocked(backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked(backend_pid, deadline)
  end

  defp do_wait_until_blocked(backend_pid, deadline) do
    [[blocking_count]] =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT cardinality(pg_blocking_pids($1))", [backend_pid]).rows
      end)

    cond do
      blocking_count > 0 ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_until_blocked(backend_pid, deadline)
    end
  end

  defp register_asset!(project, user, filename, content) do
    {:ok, %{asset_id: asset_id}} =
      Repo.transact(fn ->
        Projects.register_uploaded_asset(
          project.id,
          user.id,
          asset_attrs(project.id, filename, content),
          :generic
        )
      end)

    Repo.get!(Asset, asset_id)
  end

  defp asset_attrs(project_id, filename, content, metadata \\ %{}) do
    uuid = Ecto.UUID.generate()

    %{
      filename: filename,
      content_type: if(String.ends_with?(filename, ".webp"), do: "image/webp", else: "image/png"),
      size: byte_size(content),
      key: "projects/#{project_id}/assets/#{uuid}/#{filename}",
      url: "/media/assets/#{uuid}",
      metadata: metadata,
      blob_hash: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)
    }
  end

  defp create_scenario do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "asset-registration-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      %{user: user, project: project}
    end)
  end

  defp cleanup_scenario(project, user) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(current in Workspace, where: current.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
