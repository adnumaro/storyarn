defmodule Storyarn.Workspaces.Lifecycle.Commands.DeleteWorkspaceTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  test "storage failure does not replace workspace authorization or existence errors" do
    owner = user_fixture()
    outsider = user_fixture()
    workspace = workspace_fixture(owner)
    original = Application.fetch_env!(:storyarn, :storage)
    on_exit(fn -> Application.put_env(:storyarn, :storage, original) end)

    Application.put_env(:storyarn, :storage, original |> Keyword.put(:adapter, :local) |> Keyword.put(:upload_dir, "/"))

    assert {:error, :unsafe_storage_entry} = Projects.storage_provider_namespace_fingerprint()
    assert {:error, :unauthorized} = Workspaces.delete_workspace(user_scope_fixture(outsider), workspace.id)

    assert {:error, :workspace_not_found} =
             Workspaces.delete_workspace(user_scope_fixture(owner), 9_223_372_036_854_775_807)

    assert Repo.get!(Workspace, workspace.id)
    assert {:error, :unsafe_storage_entry} = Workspaces.delete_workspace(user_scope_fixture(owner), workspace.id)
    assert Repo.get!(Workspace, workspace.id)
  end
end
