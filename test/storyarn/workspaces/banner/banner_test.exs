defmodule Storyarn.Workspaces.BannerTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Repo
  alias Storyarn.WorkspaceBannerCleanupQueueStub, as: CleanupQueueStub
  alias Storyarn.WorkspaceBannerStorageStub, as: StorageStub
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  setup do
    StorageStub.reset()
    CleanupQueueStub.reset()

    owner = user_fixture()
    workspace = workspace_fixture(owner)

    %{
      owner: owner,
      scope: Scope.for_user(owner),
      workspace: workspace,
      storage_opts: [storage: StorageStub, cleanup_queue: CleanupQueueStub]
    }
  end

  test "uploads a validated image through the Workspace-owned use case", ctx do
    image = File.read!("test/fixtures/images/test_image.jpg")

    assert {:ok, workspace} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("banner.jpg", "image/jpeg", image),
               ctx.storage_opts
             )

    assert [{:upload, key, ^image, "image/jpeg"}] = StorageStub.calls(:upload)
    assert String.starts_with?(key, "workspaces/#{ctx.workspace.slug}/banner/")
    assert String.ends_with?(key, ".jpg")
    assert workspace.banner_url == StorageStub.url_for(key)
    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == workspace.banner_url
    assert StorageStub.calls(:delete) == []
    assert CleanupQueueStub.calls() == []

    assert {:ok, %{key: ^key, content_type: "image/jpeg"}} =
             Workspaces.get_workspace_banner(ctx.scope, ctx.workspace.slug, ctx.storage_opts)
  end

  test "reads a banner URL persisted before the Workspace-owned use case", ctx do
    legacy_key = "workspaces/#{ctx.workspace.slug}/banner/legacy-banner.jpg"
    legacy_url = StorageStub.url_for(legacy_key)
    persist_existing_banner(ctx.workspace, legacy_url)

    assert {:ok, %{key: ^legacy_key, content_type: "image/jpeg"}} =
             Workspaces.get_workspace_banner(ctx.scope, ctx.workspace.slug, ctx.storage_opts)

    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == legacy_url
    assert StorageStub.calls(:upload) == []
    assert StorageStub.calls(:delete) == []
  end

  test "rejects a currently unauthorized member before touching storage", ctx do
    admin = user_fixture()
    workspace_membership_fixture(ctx.workspace, admin, "admin")
    image = File.read!("test/fixtures/images/test_image.jpg")

    assert {:error, :unauthorized} =
             Workspaces.upload_workspace_banner(
               Scope.for_user(admin),
               ctx.workspace.id,
               upload_attrs("banner.jpg", "image/jpeg", image),
               ctx.storage_opts
             )

    assert StorageStub.calls(:upload) == []
    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == nil
  end

  test "rejects extension, claimed MIME, and real image MIME disagreement", ctx do
    jpeg = File.read!("test/fixtures/images/test_image.jpg")

    assert {:error, :invalid_banner_upload} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("banner.png", "image/png", jpeg),
               ctx.storage_opts
             )

    assert {:error, :invalid_banner_upload} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("banner.jpg", "image/jpeg", "not an image"),
               ctx.storage_opts
             )

    assert StorageStub.calls(:upload) == []
  end

  test "reauthorizes under lock and compensates the uploaded object when persistence is denied", ctx do
    image = File.read!("test/fixtures/images/test_image.jpg")
    membership = Workspaces.get_membership(ctx.workspace, ctx.owner)

    StorageStub.after_upload(fn ->
      Repo.update_all(
        from(current in WorkspaceMembership, where: current.id == ^membership.id),
        set: [role: "admin"]
      )
    end)

    assert {:error, :unauthorized} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("banner.jpg", "image/jpeg", image),
               ctx.storage_opts
             )

    assert [{:upload, key, ^image, "image/jpeg"}] = StorageStub.calls(:upload)
    assert [{:delete, ^key}] = StorageStub.calls(:delete)
    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == nil
  end

  test "persists deferred cleanup when update compensation cannot delete the object", ctx do
    image = File.read!("test/fixtures/images/test_image.jpg")
    membership = Workspaces.get_membership(ctx.workspace, ctx.owner)

    StorageStub.after_upload(fn ->
      Repo.update_all(
        from(current in WorkspaceMembership, where: current.id == ^membership.id),
        set: [role: "admin"]
      )
    end)

    StorageStub.respond(:delete, {:error, :storage_unavailable})

    assert {:error, {:workspace_banner_cleanup_deferred, :unauthorized, :storage_unavailable}} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("banner.jpg", "image/jpeg", image),
               ctx.storage_opts
             )

    assert [{:upload, key, ^image, "image/jpeg"}] = StorageStub.calls(:upload)
    assert [{:delete, ^key}] = StorageStub.calls(:delete)
    assert CleanupQueueStub.calls() == [{ctx.workspace.slug, key}]
    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == nil
  end

  test "reports the exact orphan only when delete and durable enqueue both fail", ctx do
    image = File.read!("test/fixtures/images/test_image.jpg")
    membership = Workspaces.get_membership(ctx.workspace, ctx.owner)

    StorageStub.after_upload(fn ->
      Repo.update_all(
        from(current in WorkspaceMembership, where: current.id == ^membership.id),
        set: [role: "admin"]
      )
    end)

    StorageStub.respond(:delete, {:error, :storage_unavailable})
    CleanupQueueStub.respond({:error, :queue_unavailable})

    assert {:error,
            {:workspace_banner_update_failed_with_cleanup_required, :unauthorized, key,
             %{delete: :storage_unavailable, enqueue: :queue_unavailable}}} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("banner.jpg", "image/jpeg", image),
               ctx.storage_opts
             )

    assert [{:delete, ^key}] = StorageStub.calls(:delete)
    assert CleanupQueueStub.calls() == [{ctx.workspace.slug, key}]
    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == nil
  end

  test "replacement persists a unique object before deleting the previous banner", ctx do
    old_key = "workspaces/#{ctx.workspace.slug}/banner/old-banner.jpg"

    persist_existing_banner(ctx.workspace, StorageStub.url_for(old_key))

    image = File.read!("test/fixtures/images/test_image.jpg")

    assert {:ok, workspace} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("old-banner.jpg", "image/jpeg", image),
               ctx.storage_opts
             )

    assert [{:upload, new_key, ^image, "image/jpeg"}] = StorageStub.calls(:upload)
    refute new_key == old_key
    assert workspace.banner_url == StorageStub.url_for(new_key)
    assert CleanupQueueStub.calls() == [{ctx.workspace.slug, old_key}]
    assert StorageStub.calls(:delete) == []
  end

  test "removal clears persistence and deletes only the owned previous object", ctx do
    old_key = "workspaces/#{ctx.workspace.slug}/banner/removable.jpg"

    persist_existing_banner(ctx.workspace, StorageStub.url_for(old_key))

    assert {:ok, workspace} =
             Workspaces.remove_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               ctx.storage_opts
             )

    assert workspace.banner_url == nil
    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == nil
    assert CleanupQueueStub.calls() == [{ctx.workspace.slug, old_key}]
    assert StorageStub.calls(:delete) == []
  end

  test "rolls back replacement and compensates the new object when cleanup cannot be persisted", ctx do
    old_key = "workspaces/#{ctx.workspace.slug}/banner/kept.jpg"
    persist_existing_banner(ctx.workspace, StorageStub.url_for(old_key))
    CleanupQueueStub.respond({:error, :queue_unavailable})
    image = File.read!("test/fixtures/images/test_image.jpg")

    assert {:error, {:workspace_banner_cleanup_enqueue_failed, :queue_unavailable}} =
             Workspaces.upload_workspace_banner(
               ctx.scope,
               ctx.workspace.id,
               upload_attrs("replacement.jpg", "image/jpeg", image),
               ctx.storage_opts
             )

    assert [{:upload, new_key, ^image, "image/jpeg"}] = StorageStub.calls(:upload)
    assert new_key != old_key
    assert [{:delete, ^new_key}] = StorageStub.calls(:delete)
    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == StorageStub.url_for(old_key)
  end

  test "keeps the banner reference when removal cleanup cannot be persisted", ctx do
    old_key = "workspaces/#{ctx.workspace.slug}/banner/still-current.jpg"
    old_url = StorageStub.url_for(old_key)
    persist_existing_banner(ctx.workspace, old_url)
    CleanupQueueStub.respond({:error, :queue_unavailable})

    assert {:error, {:workspace_banner_cleanup_enqueue_failed, :queue_unavailable}} =
             Workspaces.remove_workspace_banner(ctx.scope, ctx.workspace.id, ctx.storage_opts)

    assert Workspaces.get_workspace!(ctx.workspace.id).banner_url == old_url
    assert CleanupQueueStub.calls() == [{ctx.workspace.slug, old_key}]
    assert StorageStub.calls(:delete) == []
  end

  defp upload_attrs(filename, content_type, binary) do
    %{
      filename: filename,
      content_type: content_type,
      data: "data:#{content_type};base64,#{Base.encode64(binary)}"
    }
  end

  defp persist_existing_banner(workspace, url) do
    workspace
    |> Workspace.banner_changeset(%{banner_url: url})
    |> Repo.update!()
  end
end
