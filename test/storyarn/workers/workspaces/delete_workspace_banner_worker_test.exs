defmodule Storyarn.Workers.DeleteWorkspaceBannerWorkerTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Workers.DeleteWorkspaceBannerWorker
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  test "replacement commits an Oban cleanup intent and the worker deletes the obsolete object" do
    owner = user_fixture()
    scope = Scope.for_user(owner)
    workspace = workspace_fixture(owner)
    image = File.read!("test/fixtures/images/test_image.jpg")

    assert {:ok, first} =
             Workspaces.upload_workspace_banner(
               scope,
               workspace.id,
               upload_attrs(image)
             )

    {:ok, first_key} = Storage.key_from_url(first.banner_url)
    on_exit(fn -> Storage.delete(first_key) end)

    assert {:ok, replacement} =
             Workspaces.upload_workspace_banner(
               scope,
               workspace.id,
               upload_attrs(image)
             )

    {:ok, replacement_key} = Storage.key_from_url(replacement.banner_url)
    on_exit(fn -> Storage.delete(replacement_key) end)

    assert_enqueued(
      worker: DeleteWorkspaceBannerWorker,
      queue: :workspace_banner_cleanup,
      args: %{"workspace_slug" => workspace.slug, "storage_key" => first_key}
    )

    assert :ok =
             perform_job(DeleteWorkspaceBannerWorker, %{
               "workspace_slug" => workspace.slug,
               "storage_key" => first_key
             })

    assert {:error, :enoent} = Storage.stat(first_key)
    assert {:ok, _stat} = Storage.stat(replacement_key)
  end

  test "hard delete commits banner cleanup before the Workspace row disappears" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    key = "workspaces/#{workspace.slug}/banner/#{Ecto.UUID.generate()}.png"
    {:ok, url} = Storage.upload(key, "workspace banner", "image/png")
    on_exit(fn -> Storage.delete(key) end)

    workspace =
      workspace
      |> Workspace.banner_changeset(%{banner_url: url})
      |> Repo.update!()

    assert {:ok, _deleted_workspace} = Workspaces.delete_workspace(workspace)
    refute Repo.get(Workspace, workspace.id)

    assert_enqueued(
      worker: DeleteWorkspaceBannerWorker,
      queue: :workspace_banner_cleanup,
      args: %{"workspace_slug" => workspace.slug, "storage_key" => key}
    )

    assert :ok =
             perform_job(DeleteWorkspaceBannerWorker, %{
               "workspace_slug" => workspace.slug,
               "storage_key" => key
             })

    assert {:error, :enoent} = Storage.stat(key)
  end

  test "hard delete without a banner does not enqueue banner cleanup" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    assert {:ok, _deleted_workspace} = Workspaces.delete_workspace(workspace)
    refute Repo.get(Workspace, workspace.id)

    refute_enqueued(worker: DeleteWorkspaceBannerWorker)
  end

  test "worker discards a key outside the captured Workspace namespace" do
    job = %Oban.Job{
      args: %{
        "workspace_slug" => "writers-room",
        "storage_key" => "workspaces/another-workspace/banner/image.png"
      }
    }

    assert {:discard, :invalid_banner_key} = DeleteWorkspaceBannerWorker.perform(job)
  end

  defp upload_attrs(image) do
    %{
      filename: "banner.jpg",
      content_type: "image/jpeg",
      data: "data:image/jpeg;base64,#{Base.encode64(image)}"
    }
  end
end
