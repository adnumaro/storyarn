defmodule Storyarn.Projects.WorkspaceDataLifecycleTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Repo

  describe "prepare_workspace_data_hard_delete/1" do
    test "fails closed outside the canonical workspace lock without preparing cleanup" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      asset = image_asset_fixture(project, user)

      assert {:error, :snapshot_cleanup_workspace_lock_required} =
               Projects.prepare_workspace_data_hard_delete(workspace.id)

      assert Repo.get!(Asset, asset.id)
      refute Repo.exists?(StorageCleanupRequest)
    end

    test "rejects invalid workspace identities before touching Project data" do
      assert {:error, :invalid_workspace_project_cleanup_scope} =
               Projects.prepare_workspace_data_hard_delete(nil)

      assert {:error, :invalid_workspace_project_cleanup_scope} =
               Projects.prepare_workspace_data_hard_delete(-1)
    end
  end
end
