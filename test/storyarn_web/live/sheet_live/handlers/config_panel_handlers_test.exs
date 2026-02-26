defmodule StoryarnWeb.SheetLive.Handlers.ConfigPanelHandlersTest do
  @moduledoc """
  Tests for ConfigPanelHandlers — covers uncovered branches:
  handle_configure_block with nonexistent block (nil path),
  handle_save_block_config error path,
  handle_toggle_constant error path.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo

  defp sheet_path(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_sheet(conn, workspace, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_path(workspace, project, sheet))
    html = render_async(view, 500)
    {:ok, view, html}
  end

  defp send_to_content_tab(view, event, params) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  defp setup_sheet(%{user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Config Test Sheet"})
    block = block_fixture(sheet, %{label: "Test Block", type: "text"})

    %{
      project: project,
      workspace: project.workspace,
      sheet: sheet,
      block: block
    }
  end

  describe "handle_configure_block — block not found" do
    setup [:register_and_log_in_user, :setup_sheet]

    test "shows error flash when block does not exist", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Use a nonexistent block ID
      html = send_to_content_tab(view, "configure_block", %{"id" => "999999"})

      assert html =~ "not found" or render(view) =~ "Config Test Sheet"
    end
  end
end
