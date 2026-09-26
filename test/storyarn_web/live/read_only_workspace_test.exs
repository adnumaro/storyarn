defmodule StoryarnWeb.ReadOnlyWorkspaceTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.CommercialFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup do
    owner = user_fixture()
    editor = user_fixture()
    viewer = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    membership_fixture(project, editor, "editor")
    membership_fixture(project, viewer, "viewer")
    lock_account!(owner)

    %{owner: owner, editor: editor, viewer: viewer, project: project, workspace: project.workspace}
  end

  describe "the project shell" do
    test "tells the owner which limits the account exceeds and links to Plan & billing", ctx do
      {:ok, view, _html} = live(log_in_user(build_conn(), ctx.owner), project_path(ctx, "/sheets"))

      assert read_only_banner(view) == %{
               "owner" => true,
               "reasons" => ["workspaces_per_user"],
               "planPath" => "/users/settings/plan"
             }
    end

    test "tells an editor whom to ask, and nothing about the plan", ctx do
      {:ok, view, _html} = live(log_in_user(build_conn(), ctx.editor), project_path(ctx, "/sheets"))

      assert read_only_banner(view) == %{"owner" => false, "ownerName" => owner_name(ctx.owner)}
    end

    test "changes nothing for a viewer", ctx do
      {:ok, view, _html} = live(log_in_user(build_conn(), ctx.viewer), project_path(ctx, "/sheets"))

      assert read_only_banner(view) == nil
    end

    test "is back to normal once the account is within its limits", ctx do
      [extra] = ctx.owner |> Storyarn.Workspaces.list_workspaces_for_user() |> Enum.reject(&(&1.id == ctx.workspace.id))
      unlock_account!(extra)

      {:ok, view, _html} = live(log_in_user(build_conn(), ctx.editor), project_path(ctx, "/sheets"))

      assert read_only_banner(view) == nil
      assert sheet_tree(view, ctx.project)["canEdit"] == true
    end
  end

  describe "an editor in a read-only workspace" do
    setup ctx do
      %{conn: log_in_user(build_conn(), ctx.editor)}
    end

    test "sees the tools read-only but can still delete from the trees", ctx do
      sheet = sheet_fixture(ctx.project, %{name: "Old draft"})
      {:ok, view, _html} = live(ctx.conn, project_path(ctx, "/sheets"))
      tree = sheet_tree(view, ctx.project)

      assert tree["canEdit"] == false
      assert tree["canDelete"] == true

      sidebar = find_live_child(view, "sidebar-sheets-#{ctx.project.id}")
      render_click(sidebar, "create_sheet")

      # The sidebar is sticky: its refusal reaches the page's toaster.
      assert flash(view)["limit"]["message"] =~ "Contact its owner"

      render_click(sidebar, "set_pending_delete_sheet", %{"id" => sheet.id})
      render_click(sidebar, "confirm_delete_sheet")

      assert Sheets.get_sheet(ctx.project.id, sheet.id) == nil
      assert Sheets.list_all_sheets(ctx.project.id) == []
    end

    test "can delete from a dashboard and is told why an edit is refused", ctx do
      flow = flow_fixture(ctx.project, %{name: "Side quest"})
      {:ok, view, _html} = live(ctx.conn, project_path(ctx, "/flows"))

      assert LiveVue.Test.get_vue(view, name: "live/flow/dashboard/FlowDashboard").props["row-actions"] ==
               %{"setMain" => false, "delete" => true}

      render_hook(view, "set_main", %{"id" => flow.id})

      assert flash(view)["limit"] == %{
               "message" =>
                 "This workspace is read-only. Contact its owner, #{owner_name(ctx.owner)}, to edit it again.",
               "planPath" => nil
             }

      refute Flows.get_flow(ctx.project.id, flow.id).is_main

      render_hook(view, "delete_flow", %{"id" => flow.id})

      assert Flows.get_flow(ctx.project.id, flow.id) == nil
    end
  end

  describe "the owner of a read-only workspace" do
    setup ctx do
      %{conn: log_in_user(build_conn(), ctx.owner)}
    end

    test "is told why an edit is refused, with the link to Plan & billing", ctx do
      flow = flow_fixture(ctx.project)
      {:ok, view, _html} = live(ctx.conn, project_path(ctx, "/flows"))

      render_hook(view, "set_main", %{"id" => flow.id})

      assert flash(view)["limit"]["planPath"] == "/users/settings/plan"
      assert flash(view)["limit"]["message"] =~ "your account is over its plan's limits"
    end

    test "can empty the trash but not restore from it", ctx do
      kept = sheet_fixture(ctx.project, %{name: "Kept in trash"})
      purged = sheet_fixture(ctx.project, %{name: "Purged"})
      {:ok, _deleted} = Sheets.delete_sheet(kept)
      {:ok, _deleted} = Sheets.delete_sheet(purged)

      {:ok, view, _html} = live(ctx.conn, project_path(ctx, "/settings/trash"))

      assert LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsTrash").props["can-restore"] ==
               false

      render_hook(view, "restore_item", %{"type" => "sheet", "id" => kept.id})
      render_hook(view, "delete_item", %{"type" => "sheet", "id" => purged.id})

      assert Sheets.get_sheet(ctx.project.id, kept.id) == nil
      assert Sheets.get_trashed_sheet(ctx.project.id, kept.id)
      assert Sheets.get_trashed_sheet(ctx.project.id, purged.id) == nil
    end

    test "can delete the project, whose settings stay locked", ctx do
      {:ok, view, _html} = live(ctx.conn, project_path(ctx, "/settings"))
      general = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsGeneral")

      assert general.props["read-only"] == true
      assert general.props["can-manage-project"] == true

      assert {:error, {:live_redirect, _redirect}} = render_hook(view, "delete_project", %{})
      assert {:error, :not_found} = Projects.get_project(user_scope_fixture(ctx.owner), ctx.project.id)
    end

    test "cannot export", ctx do
      language_fixture(ctx.project, %{locale_code: "es", name: "Spanish"})

      assert ctx.conn |> get(project_path(ctx, "/export/unity")) |> response(403) =~ "read-only"

      assert ctx.conn |> get(project_path(ctx, "/localization/export/csv/es")) |> json_response(403) == %{
               "error" => "read_only"
             }
    end
  end

  defp project_path(ctx, suffix), do: "/workspaces/#{ctx.workspace.slug}/projects/#{ctx.project.slug}#{suffix}"

  defp read_only_banner(view), do: LiveVue.Test.get_vue(view, name: "live/layouts/project/Layout").props["read-only"]

  defp flash(view), do: LiveVue.Test.get_vue(view, name: "live/layouts/flash/FlashGroup").props["flash"]

  defp sheet_tree(view, project) do
    view
    |> find_live_child("sidebar-sheets-#{project.id}")
    |> LiveVue.Test.get_vue(name: "live/sheet/sidebar/SheetSidebar")
    |> Map.fetch!(:props)
    |> Map.fetch!("sidebar-props")
  end

  defp owner_name(owner), do: owner.display_name || owner.email
end
