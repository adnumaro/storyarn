defmodule StoryarnWeb.SettingsLive.WorkspaceProjectsPageTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  defp get_projects_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/WorkspaceSettingsProjects")
  end

  describe "merged page" do
    test "lists the projects retained in the workspace trash", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      project = project_fixture(owner, %{workspace: workspace, name: "Old prologue"})

      project
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now(), deleted_by_id: owner.id)
      |> Repo.update!()

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/projects")

      vue = get_projects_vue(view)
      assert [deleted] = vue.props["deleted-projects"]
      assert deleted["name"] == "Old prologue"
      assert deleted["deletedTimeAgo"] =~ "Deleted"
      assert deleted["deletedByText"] =~ owner.email
      assert vue.props["imports"] == []
    end

    test "redirects the former imports and deleted-projects pages here", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      target = ~p"/users/settings/workspaces/#{workspace.slug}/projects"
      conn = log_in_user(conn, owner)

      assert {:error, {:live_redirect, %{to: ^target}}} =
               live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/imports")

      assert {:error, {:live_redirect, %{to: ^target}}} =
               live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/deleted-projects")
    end
  end
end
