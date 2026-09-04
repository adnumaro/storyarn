defmodule Storyarn.Projects.Versioning.WorkspaceSnapshotImportNamespaceTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Platform.ObjectStorage.Adapters.Local
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImports
  alias Storyarn.Repo
  alias Storyarn.SnapshotReadSwitchStorage

  setup do
    original_storage = Application.get_env(:storyarn, :storage, [])
    base = Path.join([File.cwd!(), "test", "tmp", "eng117-#{System.unique_integer([:positive])}"])
    root_a = Path.join(base, "a")
    root_b = Path.join(base, "b")
    File.mkdir_p!(root_a)
    File.mkdir_p!(root_b)

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      File.rm_rf!(base)
    end)

    configure_local(root_a)

    user = user_fixture()
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)

    %{scope: scope, workspace: workspace, root_a: root_a, root_b: root_b}
  end

  test "cancel keeps the original namespace owner until cleanup can use that namespace", context do
    {upload, fingerprint_a} = prepare_upload_in_namespace_a!(context)
    put_archive!(upload.archive_storage_key, "namespace-a")

    configure_local(context.root_b)
    assert {:ok, fingerprint_b} = ObjectStorage.namespace_fingerprint()
    refute fingerprint_b == fingerprint_a
    put_archive!(upload.archive_storage_key, "namespace-b")

    assert {:error, :workspace_snapshot_import_storage_namespace_mismatch} =
             Projects.cancel_workspace_snapshot_upload(context.scope, context.workspace.id, upload.id)

    assert Repo.get!(WorkspaceSnapshotImport, upload.id).provider_namespace_fingerprint == fingerprint_a
    assert cleanup_requests(upload.archive_storage_key) == []
    assert archive_exists?(context.root_a, upload.archive_storage_key)
    assert archive_exists?(context.root_b, upload.archive_storage_key)

    configure_local(context.root_a)

    assert {:ok, _cancelled} =
             Projects.cancel_workspace_snapshot_upload(context.scope, context.workspace.id, upload.id)

    refute Repo.get(WorkspaceSnapshotImport, upload.id)

    assert [%StorageCleanupRequest{provider_namespace_fingerprint: ^fingerprint_a}] =
             cleanup_requests(upload.archive_storage_key)

    refute archive_exists?(context.root_a, upload.archive_storage_key)
    assert archive_exists?(context.root_b, upload.archive_storage_key)
  end

  test "TTL reconciliation fails closed across namespace drift and succeeds in the original namespace", context do
    {upload, fingerprint_a} = prepare_upload_in_namespace_a!(context)
    put_archive!(upload.archive_storage_key, "namespace-a")

    Repo.update_all(
      Ecto.Query.from(import in WorkspaceSnapshotImport, where: import.id == ^upload.id),
      set: [updated_at: ~U[2020-01-01 00:00:00Z]]
    )

    configure_local(context.root_b)
    put_archive!(upload.archive_storage_key, "namespace-b")

    assert %{candidate_count: 1, changed_count: 0, failure_count: 1} =
             Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(upload_ttl_seconds: 1)

    assert Repo.get!(WorkspaceSnapshotImport, upload.id).provider_namespace_fingerprint == fingerprint_a
    assert cleanup_requests(upload.archive_storage_key) == []
    assert archive_exists?(context.root_a, upload.archive_storage_key)
    assert archive_exists?(context.root_b, upload.archive_storage_key)

    configure_local(context.root_a)

    assert %{candidate_count: 1, changed_count: 1, failure_count: 0} =
             Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(upload_ttl_seconds: 1)

    refute Repo.get(WorkspaceSnapshotImport, upload.id)

    assert [%StorageCleanupRequest{provider_namespace_fingerprint: ^fingerprint_a}] =
             cleanup_requests(upload.archive_storage_key)

    refute archive_exists?(context.root_a, upload.archive_storage_key)
    assert archive_exists?(context.root_b, upload.archive_storage_key)
  end

  test "a legacy upload without provider identity fails closed", context do
    {upload, _fingerprint_a} = prepare_upload_in_namespace_a!(context)
    put_archive!(upload.archive_storage_key, "legacy")

    Repo.update_all(
      Ecto.Query.from(import in WorkspaceSnapshotImport, where: import.id == ^upload.id),
      set: [provider_namespace_fingerprint: nil]
    )

    assert {:error, :workspace_snapshot_import_storage_namespace_mismatch} =
             Projects.cancel_workspace_snapshot_upload(context.scope, context.workspace.id, upload.id)

    assert is_nil(Repo.get!(WorkspaceSnapshotImport, upload.id).provider_namespace_fingerprint)
    assert cleanup_requests(upload.archive_storage_key) == []
    assert archive_exists?(context.root_a, upload.archive_storage_key)
  end

  for operation <- [:cancel, :ttl] do
    @tag operation: operation
    test "#{operation} rejects namespace drift after the initial cleanup observation",
         %{operation: operation} = context do
      {upload, fingerprint_a} = prepare_upload_in_namespace_a!(context)
      put_archive!(upload.archive_storage_key, "namespace-a")

      if operation == :ttl do
        Repo.update_all(
          Ecto.Query.from(import in WorkspaceSnapshotImport, where: import.id == ^upload.id),
          set: [updated_at: ~U[2020-01-01 00:00:00Z]]
        )
      end

      configure_local(context.root_b)
      assert {:ok, fingerprint_b} = ObjectStorage.namespace_fingerprint()
      refute fingerprint_b == fingerprint_a
      put_archive!(upload.archive_storage_key, "namespace-b")

      configure_local(context.root_a)
      {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})

      on_exit(fn ->
        if Process.whereis(SnapshotReadSwitchStorage), do: Agent.stop(SnapshotReadSwitchStorage)
      end)

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(Application.fetch_env!(:storyarn, :storage), :adapter, SnapshotReadSwitchStorage)
      )

      test_process = self()

      SnapshotReadSwitchStorage.observe_namespace(fn observed ->
        assert observed == fingerprint_a
        configure_local(context.root_b)
        send(test_process, :cleanup_namespace_switched)
      end)

      case operation do
        :cancel ->
          assert {:error, :workspace_snapshot_import_storage_namespace_mismatch} =
                   Projects.cancel_workspace_snapshot_upload(context.scope, context.workspace.id, upload.id)

        :ttl ->
          assert %{candidate_count: 1, changed_count: 0, failure_count: 1} =
                   Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(upload_ttl_seconds: 1)
      end

      assert_received :cleanup_namespace_switched
      assert Repo.get!(WorkspaceSnapshotImport, upload.id).provider_namespace_fingerprint == fingerprint_a
      assert cleanup_requests(upload.archive_storage_key) == []
      assert File.read!(Path.join(context.root_a, upload.archive_storage_key)) == "namespace-a"
      assert File.read!(Path.join(context.root_b, upload.archive_storage_key)) == "namespace-b"
    end
  end

  defp prepare_upload_in_namespace_a!(context) do
    assert {:ok, fingerprint} = ObjectStorage.namespace_fingerprint()

    assert {:ok, upload} =
             WorkspaceSnapshotImports.prepare_upload(context.scope, context.workspace, %{
               original_filename: "namespace.zip",
               archive_size_bytes: 1
             })

    assert upload.provider_namespace_fingerprint == fingerprint
    assert Repo.get!(WorkspaceSnapshotImport, upload.id).provider_namespace_fingerprint == fingerprint
    {upload, fingerprint}
  end

  defp configure_local(root) do
    Application.put_env(:storyarn, :storage,
      adapter: :local,
      upload_dir: root,
      public_path: "/uploads"
    )
  end

  defp put_archive!(key, contents) do
    assert {:ok, _result} = Local.upload(key, contents, "application/zip")
  end

  defp archive_exists?(root, key), do: File.exists?(Path.join(root, key))

  defp cleanup_requests(key) do
    StorageCleanupRequest
    |> Repo.all()
    |> Enum.filter(&(key in &1.storage_keys))
  end
end
