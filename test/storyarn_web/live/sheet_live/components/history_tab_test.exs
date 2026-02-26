defmodule StoryarnWeb.SheetLive.Components.HistoryTabTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.SheetLive.Components.HistoryTab

  # A minimal LiveView host for testing the HistoryTab LiveComponent.
  defmodule TestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <.live_component
        module={HistoryTab}
        id="test-history-tab"
        sheet={@sheet}
        project={@project}
        current_user_id={@current_user_id}
        can_edit={@can_edit}
      />
      """
    end

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         sheet: session["sheet"],
         project: session["project"],
         current_user_id: session["current_user_id"],
         can_edit: session["can_edit"]
       )}
    end
  end

  describe "render" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project)
      %{project: project, sheet: sheet}
    end

    test "renders the history tab with version history section", %{
      conn: conn,
      project: project,
      sheet: sheet,
      user: user
    } do
      {:ok, _view, html} =
        live_isolated(conn, TestLive,
          session: %{
            "sheet" => sheet,
            "project" => project,
            "current_user_id" => user.id,
            "can_edit" => true
          }
        )

      assert html =~ "Version History"
    end
  end
end
