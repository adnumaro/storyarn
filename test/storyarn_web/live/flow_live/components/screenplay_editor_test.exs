defmodule StoryarnWeb.FlowLive.Components.ScreenplayEditorTest do
  @moduledoc """
  Tests for the ScreenplayEditor LiveComponent.

  Tests are executed through the FlowLive.Show parent LiveView,
  which is the only consumer of this component.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  # Simulates the FlowLoader JS hook: triggers the event + waits for start_async
  defp load_flow(view) do
    render_click(view, "load_flow_data", %{})
    render_async(view, 500)
  end

  # Opens the screenplay editor for a dialogue node
  defp open_screenplay_editor(view, node) do
    render_click(view, "node_selected", %{"id" => node.id})
    render_click(view, "open_screenplay", %{})
  end

  # Returns the inner div ID for the screenplay editor
  defp editor_target(_node) do
    "#dialogue-screenplay-editor"
  end

  describe "rendering" do
    setup :register_and_log_in_user

    test "renders the screenplay editor when opened for a dialogue node", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>Hello world</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "loc_001",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Should render the screenplay editor overlay
      assert html =~ "dialogue-screenplay-editor"
      assert html =~ "Back to canvas"
      # Footer status bar
      assert html =~ "to close"
      # Tabs
      assert html =~ "Responses"
      assert html =~ "Settings"
      # Text editor container
      assert html =~ "screenplay-text-editor-#{node.id}"
      # Speaker selector
      assert html =~ "SELECT SPEAKER"
      # Stage directions placeholder
      assert html =~ "(stage directions)"
    end

    test "renders word count in footer", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>one two three four five</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # 5 words in the text
      assert html =~ "5 words"
    end

    test "renders singular word count for 1 word", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>hello</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      assert html =~ "1 word"
    end

    test "renders 0 words for empty text", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      assert html =~ "0 words"
    end

    test "renders speaker name in footer when speaker is set", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      sheet = sheet_fixture(project, %{name: "Jaime"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => sheet.id,
            "text" => "<p>Hello</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Speaker name should appear in the footer
      assert html =~ "Jaime"
      # Speaker option should be uppercased in the selector
      assert html =~ "JAIME"
    end

    test "renders speaker options from all_sheets", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      _sheet1 = sheet_fixture(project, %{name: "Alice"})
      _sheet2 = sheet_fixture(project, %{name: "Bob"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Both sheets should appear as speaker options (uppercased)
      assert html =~ "ALICE"
      assert html =~ "BOB"
    end

    test "renders audio indicator when audio_asset_id is set", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => "some-audio-id"
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Should show audio indicator in footer
      assert html =~ "Audio attached"
    end

    test "does not render audio indicator when no audio", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      refute html =~ "Audio attached"
    end

    test "renders responses tab with response cards", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>Hello</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [
              %{
                "id" => "resp-1",
                "text" => "Yes, I agree",
                "condition" => "",
                "instruction" => ""
              },
              %{"id" => "resp-2", "text" => "No way", "condition" => "", "instruction" => ""}
            ],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Responses should be visible (default tab)
      assert html =~ "Yes, I agree"
      assert html =~ "No way"
      # Response count badge
      assert html =~ "2"
      # Add response button
      assert html =~ "Add response"
    end

    test "renders responses with advanced section indicator when condition is set", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>Hello</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [
              %{
                "id" => "resp-1",
                "text" => "Conditional response",
                "condition" => %{
                  "logic" => "all",
                  "rules" => [
                    %{
                      "sheet" => "mc",
                      "variable" => "health",
                      "operator" => "greater_than",
                      "value" => "50"
                    }
                  ]
                },
                "instruction" => ""
              }
            ],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Advanced section should be present
      assert html =~ "Advanced"
      assert html =~ "Conditional response"
    end
  end

  describe "switch_tab" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>Hello</p>",
            "stage_directions" => "",
            "menu_text" => "Short menu text",
            "technical_id" => "tech_001",
            "localization_id" => "loc_001",
            "responses" => [
              %{"id" => "resp-1", "text" => "OK", "condition" => "", "instruction" => ""}
            ],
            "audio_asset_id" => nil
          }
        })

      %{project: project, flow: flow, node: node}
    end

    test "defaults to responses tab", %{
      conn: conn,
      project: project,
      flow: flow,
      node: node
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Responses tab should be active
      assert html =~ "tab-active"
      # Response content should be visible
      assert html =~ "OK"
      assert html =~ "Add response"
    end

    test "switches to settings tab", %{
      conn: conn,
      project: project,
      flow: flow,
      node: node
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Click on the Settings tab
      html =
        view
        |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
        |> render_click()

      # Settings tab content should be visible
      assert html =~ "Menu Text"
      assert html =~ "Technical ID"
      assert html =~ "Localization ID"
      assert html =~ "Audio"
    end

    test "settings tab shows menu text value", %{
      conn: conn,
      project: project,
      flow: flow,
      node: node
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      html =
        view
        |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
        |> render_click()

      assert html =~ "Short menu text"
    end

    test "settings tab shows technical_id and localization_id", %{
      conn: conn,
      project: project,
      flow: flow,
      node: node
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      html =
        view
        |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
        |> render_click()

      assert html =~ "tech_001"
      assert html =~ "loc_001"
    end

    test "switches back to responses tab from settings", %{
      conn: conn,
      project: project,
      flow: flow,
      node: node
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to settings
      view
      |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
      |> render_click()

      # Switch back to responses
      html =
        view
        |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=responses]")
        |> render_click()

      assert html =~ "Add response"
      assert html =~ "OK"
    end
  end

  describe "update_speaker" do
    setup :register_and_log_in_user

    test "updates speaker_sheet_id on the node", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      sheet = sheet_fixture(project, %{name: "Narrator"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Update the speaker (the form has phx-change, target the form directly)
      html =
        view
        |> element(editor_target(node) <> " [phx-change=update_speaker]")
        |> render_change(%{"speaker_sheet_id" => to_string(sheet.id)})

      # Speaker name should appear in footer
      assert html =~ "Narrator"

      # Verify in DB
      updated_node = Flows.get_node!(flow.id, node.id)
      assert to_string(updated_node.data["speaker_sheet_id"]) == to_string(sheet.id)
    end

    test "clears speaker when selecting empty option", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      sheet = sheet_fixture(project, %{name: "Speaker"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => sheet.id,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Clear the speaker (target the form, not the select)
      view
      |> element(editor_target(node) <> " [phx-change=update_speaker]")
      |> render_change(%{"speaker_sheet_id" => ""})

      # Verify in DB - speaker_sheet_id should be empty
      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["speaker_sheet_id"] == ""
    end
  end

  describe "update_stage_directions" do
    setup :register_and_log_in_user

    test "updates stage_directions on the node", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Update stage directions
      view
      |> element(editor_target(node) <> " [phx-change=update_stage_directions]")
      |> render_change(%{"stage_directions" => "walks slowly to the door"})

      # Verify in DB
      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["stage_directions"] == "walks slowly to the door"
    end
  end

  describe "update_node_text" do
    setup :register_and_log_in_user

    test "updates text on the node via TipTap event", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # The TipTap editor sends update_node_text to the ScreenplayEditor component
      target = editor_target(node)

      view
      |> element(target)
      |> render_hook("update_node_text", %{
        "id" => to_string(node.id),
        "content" => "<p>New dialogue text with <em>emphasis</em></p>"
      })

      # Verify in DB
      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["text"] =~ "New dialogue text"
    end
  end

  describe "settings tab updates" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      %{project: project, flow: flow, node: node}
    end

    test "updates menu_text", %{conn: conn, project: project, flow: flow, node: node} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to settings tab
      view
      |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
      |> render_click()

      # Update menu text
      view
      |> element(editor_target(node) <> " [phx-change=update_menu_text]")
      |> render_change(%{"menu_text" => "Go left"})

      # Verify in DB
      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["menu_text"] == "Go left"
    end

    test "updates technical_id", %{conn: conn, project: project, flow: flow, node: node} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to settings tab
      view
      |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
      |> render_click()

      # Update technical ID
      view
      |> element(editor_target(node) <> " [phx-change=update_technical_id]")
      |> render_change(%{"technical_id" => "dlg_chapter1_001"})

      # Verify in DB
      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["technical_id"] == "dlg_chapter1_001"
    end

    test "updates localization_id", %{conn: conn, project: project, flow: flow, node: node} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to settings tab
      view
      |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
      |> render_click()

      # Update localization ID
      view
      |> element(editor_target(node) <> " [phx-change=update_localization_id]")
      |> render_change(%{"localization_id" => "loc_chapter1_001"})

      # Verify in DB
      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["localization_id"] == "loc_chapter1_001"
    end
  end

  describe "read-only mode (can_edit: false)" do
    setup :register_and_log_in_user

    test "viewer sees read-only screenplay editor", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      flow = flow_fixture(project, %{name: "Test Flow"})
      sheet = sheet_fixture(project, %{name: "Guard"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => sheet.id,
            "text" => "<p>Halt! Who goes there?</p>",
            "stage_directions" => "standing at the gate",
            "menu_text" => "Guard dialogue",
            "technical_id" => "guard_001",
            "localization_id" => "loc_guard_001",
            "responses" => [
              %{
                "id" => "resp-1",
                "text" => "I am a friend",
                "condition" => "",
                "instruction" => ""
              }
            ],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Should show speaker as read-only text, not a select
      assert html =~ "Guard"
      assert html =~ "sp-character-content"

      # Stage directions should be read-only text
      assert html =~ "standing at the gate"

      # Responses should be read-only text
      assert html =~ "I am a friend"

      # Should NOT show editable controls
      refute html =~ "dialogue-sp-select"
      refute html =~ "Add response"
    end

    test "viewer sees read-only settings tab", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "Choice text",
            "technical_id" => "tech_123",
            "localization_id" => "loc_123",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to settings tab
      html =
        view
        |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
        |> render_click()

      # Menu text should be visible but read-only
      assert html =~ "Choice text"
    end

    test "update_node_field is no-op when can_edit is false", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>Original text</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Try to update text through the hook event - should be blocked by can_edit: false
      target = editor_target(node)

      view
      |> element(target)
      |> render_hook("update_node_text", %{
        "id" => to_string(node.id),
        "content" => "<p>Hacked text</p>"
      })

      # Verify the node was NOT changed in DB
      db_node = Flows.get_node!(flow.id, node.id)
      assert db_node.data["text"] == "<p>Original text</p>"
    end
  end

  describe "proxy events" do
    setup :register_and_log_in_user

    test "mention_suggestions proxies to parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Send mention_suggestions event to the component - should not crash
      target = editor_target(node)

      html =
        view
        |> element(target)
        |> render_hook("mention_suggestions", %{"query" => "jai"})

      # View should still be alive
      assert html =~ "dialogue-screenplay-editor"
    end

    test "variable_suggestions proxies to parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Send variable_suggestions event - should not crash
      target = editor_target(node)

      html =
        view
        |> element(target)
        |> render_hook("variable_suggestions", %{"query" => "health"})

      assert html =~ "dialogue-screenplay-editor"
    end

    test "resolve_variable_defaults proxies to parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Send resolve_variable_defaults event - should not crash
      target = editor_target(node)

      html =
        view
        |> element(target)
        |> render_hook("resolve_variable_defaults", %{"refs" => ["mc.jaime.health"]})

      assert html =~ "dialogue-screenplay-editor"
    end
  end

  describe "update with various node data shapes" do
    setup :register_and_log_in_user

    test "handles node with nil data fields gracefully", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      # Minimal data - many fields nil/missing
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => nil,
            "stage_directions" => nil,
            "menu_text" => nil,
            "technical_id" => nil,
            "localization_id" => nil,
            "responses" => nil,
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Should render without crashing
      assert html =~ "dialogue-screenplay-editor"
      assert html =~ "0 words"
    end

    test "handles node with empty responses list", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Should show add response button but no response cards
      assert html =~ "Add response"
      # No response count badge should appear (badge only shown if > 0)
      refute html =~ "badge-ghost"
    end

    test "handles node with empty string audio_asset_id", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      # Empty string should be treated same as nil
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => ""
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Empty string audio should not show audio indicator
      refute html =~ "Audio attached"
    end

    test "handles node with speaker_sheet_id referencing non-existent sheet", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      # Use a fake sheet ID that doesn't exist
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => 999_999,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # Should render without crashing - no speaker name in footer
      assert html =~ "dialogue-screenplay-editor"
    end

    test "handles rich text with HTML tags in word count", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>Hello <strong>brave</strong> <em>adventurer</em>!</p>",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      html = open_screenplay_editor(view, node)

      # HTML tags stripped: "Hello brave adventurer !" = 4 tokens (! separated by tag boundary)
      assert html =~ "4 words"
    end
  end

  describe "render_tab fallback" do
    setup :register_and_log_in_user

    test "unknown tab renders empty content", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to an unknown tab - should render empty but not crash
      html =
        view
        |> element(editor_target(node))
        |> render_hook("switch_tab", %{"tab" => "nonexistent"})

      # Should still render the editor frame
      assert html =~ "dialogue-screenplay-editor"
    end
  end

  describe "localization_id copy button" do
    setup :register_and_log_in_user

    test "shows copy button when localization_id is set", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "loc_test_copy",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to settings
      html =
        view
        |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
        |> render_click()

      # Copy button should be present with the localization_id as data attribute
      assert html =~ "data-copy-text=\"loc_test_copy\""
    end

    test "does not show copy button when localization_id is empty", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "",
            "menu_text" => "",
            "technical_id" => "",
            "localization_id" => "",
            "responses" => [],
            "audio_asset_id" => nil
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)
      open_screenplay_editor(view, node)

      # Switch to settings
      html =
        view
        |> element(editor_target(node) <> " [phx-click=switch_tab][phx-value-tab=settings]")
        |> render_click()

      # Copy button should NOT be present
      refute html =~ "data-copy-text"
    end
  end
end
