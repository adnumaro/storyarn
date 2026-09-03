defmodule StoryarnWeb.Live.Hooks.SettingsNavTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts
  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.Live.Hooks.SettingsNav

  describe "build_nav/1 in account scope" do
    test "lists only workspaces with settings access and marks ownership" do
      user = user_fixture()
      owned = Workspaces.get_default_workspace(user)
      admin_of = workspace_fixture(user_fixture(), %{name: "Admin here"})
      member_of = workspace_fixture(user_fixture(), %{name: "Member here"})
      viewer_of = workspace_fixture(user_fixture(), %{name: "Viewer here"})
      workspace_membership_fixture(admin_of, user, "admin")
      workspace_membership_fixture(member_of, user, "member")
      workspace_membership_fixture(viewer_of, user, "viewer")

      nav = SettingsNav.build_nav(account_assigns(user))

      assert Enum.map(nav.workspaces, &{&1.slug, &1.access, &1.owner}) == [
               {owned.slug, "manage", true},
               {admin_of.slug, "manage", false},
               {member_of.slug, "general", false}
             ]

      assert nav.workspace.slug == owned.slug
      assert nav.project == nil
      assert nav.projects == []
      refute Enum.any?(nav.workspaces, &(&1.slug == viewer_of.slug))
    end

    test "prefers the scoped workspace over the first accessible one" do
      user = user_fixture()
      other = workspace_fixture(user_fixture(), %{name: "Other"})
      workspace_membership_fixture(other, user, "admin")

      nav =
        user
        |> account_assigns()
        |> Map.put(:workspace, other)
        |> SettingsNav.build_nav()

      assert nav.workspace.slug == other.slug
    end

    test "offers the projects of the current workspace the user can act on" do
      user = user_fixture()
      workspace = Workspaces.get_default_workspace(user)
      owned = project_fixture(user, %{workspace: workspace, name: "Veilbreak"})

      nav = SettingsNav.build_nav(account_assigns(user))

      assert nav.project == nil
      assert Enum.map(nav.projects, &{&1.slug, &1.access}) == [{owned.slug, "owner"}]
    end

    test "hides the workspace group when the scoped workspace is only viewed" do
      user = user_fixture()
      viewer_of = workspace_fixture(user_fixture(), %{name: "Viewer here"})
      workspace_membership_fixture(viewer_of, user, "viewer")

      nav =
        user
        |> account_assigns()
        |> Map.put(:workspace, viewer_of)
        |> SettingsNav.build_nav()

      assert nav.workspace == nil
    end
  end

  describe "build_nav/1 in project scope" do
    test "marks the owner and offers the other projects the user can act on" do
      owner = user_fixture()
      workspace = Workspaces.get_default_workspace(owner)
      project = project_fixture(owner, %{workspace: workspace, name: "Veilbreak"})
      sibling = project_fixture(owner, %{workspace: workspace, name: "Ashfall"})

      nav = SettingsNav.build_nav(project_assigns(owner, workspace, project))

      assert nav.project.slug == project.slug
      assert nav.project.access == "owner"
      assert nav.project.workspaceSlug == workspace.slug
      assert Enum.sort(Enum.map(nav.projects, & &1.slug)) == Enum.sort([project.slug, sibling.slug])
    end

    test "marks an editor and drops projects the user only views from the switcher" do
      owner = user_fixture()
      editor = user_fixture()
      workspace = Workspaces.get_default_workspace(owner)
      workspace_membership_fixture(workspace, editor, "admin")
      project = project_fixture(owner, %{workspace: workspace, name: "Veilbreak"})
      viewed = project_fixture(owner, %{workspace: workspace, name: "Read only"})
      membership_fixture(project, editor, "editor")
      membership_fixture(viewed, editor, "viewer")

      nav = SettingsNav.build_nav(project_assigns(editor, workspace, project))

      assert nav.project.access == "editor"
      assert Enum.map(nav.projects, & &1.slug) == [project.slug]
    end

    test "marks a viewer so the rail can hide project settings" do
      owner = user_fixture()
      viewer = user_fixture()
      workspace = Workspaces.get_default_workspace(owner)
      workspace_membership_fixture(workspace, viewer, "viewer")
      project = project_fixture(owner, %{workspace: workspace, name: "Veilbreak"})

      nav = SettingsNav.build_nav(project_assigns(viewer, workspace, project))

      assert nav.project.access == "viewer"
      assert nav.projects == []
      assert nav.workspace == nil
    end
  end

  # Mirrors what `UserAuth.on_mount(:load_workspaces)` assigns for every page.
  defp account_assigns(user) do
    scope = Accounts.scope_for_user(user)
    workspace_data = Workspaces.list_workspaces(scope)

    %{
      current_scope: scope,
      workspaces: Enum.map(workspace_data, & &1.workspace),
      managed_workspace_slugs:
        workspace_data
        |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_settings))
        |> MapSet.new(& &1.workspace.slug),
      general_workspace_slugs:
        workspace_data
        |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_general_settings))
        |> MapSet.new(& &1.workspace.slug)
    }
  end

  # Mirrors what `ProjectScope.on_mount(:load_project)` adds on project pages.
  defp project_assigns(user, workspace, project) do
    assigns = account_assigns(user)

    {:ok, project, membership} =
      Projects.get_project_by_slugs(assigns.current_scope, workspace.slug, project.slug)

    assigns
    |> Map.put(:project, project)
    |> Map.put(:workspace, project.workspace)
    |> Map.put(:membership, membership)
  end
end
