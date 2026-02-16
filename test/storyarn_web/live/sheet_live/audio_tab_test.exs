defmodule StoryarnWeb.SheetLive.Components.AudioTabTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias StoryarnWeb.SheetLive.Components.AudioTab

  # A minimal LiveView host for testing the AudioTab LiveComponent.
  defmodule TestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <.live_component
        module={AudioTab}
        id="audio-tab"
        project={@project}
        workspace={@workspace}
        sheet={@sheet}
        can_edit={@can_edit}
        current_user={@current_user}
      />
      """
    end

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         project: session["project"],
         workspace: session["workspace"],
         sheet: session["sheet"],
         can_edit: session["can_edit"] || false,
         current_user: session["current_user"]
       )}
    end
  end

  defp mount_tab(conn, project, workspace, sheet, opts \\ []) do
    live_isolated(conn, TestLive,
      session: %{
        "project" => project,
        "workspace" => workspace,
        "sheet" => sheet,
        "can_edit" => Keyword.get(opts, :can_edit, false),
        "current_user" => Keyword.get(opts, :current_user)
      }
    )
  end

  describe "audio tab" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user)
      workspace = Storyarn.Repo.preload(project, :workspace).workspace
      sheet = sheet_fixture(project, %{name: "Old Merchant"})
      %{project: project, workspace: workspace, sheet: sheet}
    end

    test "renders empty state when no dialogue nodes reference this sheet", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet
    } do
      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ "No voice lines"
      assert html =~ "Dialogue nodes using this sheet as speaker will appear here."
    end

    test "lists dialogue nodes where sheet is speaker", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet
    } do
      flow = flow_fixture(project, %{name: "Intro Flow"})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "<p>Welcome traveler!</p>"}
      })

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "<p>What do you need?</p>"}
      })

      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ "Voice Lines"
      assert html =~ "Welcome traveler!"
      assert html =~ "What do you need?"
    end

    test "shows flow name as link", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet
    } do
      flow = flow_fixture(project, %{name: "Quest Flow"})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "<p>Hello</p>"}
      })

      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ "Quest Flow"
      assert html =~ "/flows/#{flow.id}"
    end

    test "shows truncated text preview", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet
    } do
      long_text =
        "<p>#{String.duplicate("This is a very long dialogue line. ", 10)}</p>"

      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => long_text}
      })

      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ "..."
      refute html =~ long_text
    end

    test "shows 'No audio' badge when audio_asset_id is nil", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet
    } do
      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "<p>Hi</p>", "audio_asset_id" => nil}
      })

      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ "No audio"
      refute html =~ "<audio"
    end

    test "shows audio filename and player when audio_asset_id is set", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet,
      user: user
    } do
      audio = audio_asset_fixture(project, user, %{filename: "merchant_hello.mp3"})
      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => sheet.id,
          "text" => "<p>Greetings</p>",
          "audio_asset_id" => audio.id
        }
      })

      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ "merchant_hello.mp3"
      assert html =~ "<audio"
    end

    test "groups lines by flow", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet
    } do
      flow1 = flow_fixture(project, %{name: "Alpha Flow"})
      flow2 = flow_fixture(project, %{name: "Beta Flow"})

      node_fixture(flow1, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "<p>Line from Alpha</p>"}
      })

      node_fixture(flow2, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "<p>Line from Beta</p>"}
      })

      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ "Alpha Flow"
      assert html =~ "Beta Flow"
      assert html =~ "Line from Alpha"
      assert html =~ "Line from Beta"
    end

    test "shows count badge", %{
      conn: conn,
      project: project,
      workspace: workspace,
      sheet: sheet
    } do
      flow = flow_fixture(project)

      for i <- 1..3 do
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => sheet.id, "text" => "<p>Line #{i}</p>"}
        })
      end

      {:ok, _view, html} = mount_tab(conn, project, workspace, sheet)

      assert html =~ ">3</span>"
    end
  end
end
