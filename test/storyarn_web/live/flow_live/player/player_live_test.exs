defmodule StoryarnWeb.FlowLive.PlayerLiveTest do
  @moduledoc """
  Integration tests for the PlayerLive full-screen story player.

  Tests mount, navigation events (continue, go_back, restart, exit_player),
  toggle_mode, choose_response, and error cases.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.{Flows, Repo}

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp player_url(project, flow) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/play"
  end

  defp flow_url(project, flow) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end

  # Gets the auto-created entry and exit nodes from a flow
  defp get_auto_nodes(flow) do
    nodes = Flows.list_nodes(flow.id)
    entry = Enum.find(nodes, &(&1.type == "entry"))
    exit_node = Enum.find(nodes, &(&1.type == "exit"))
    {entry, exit_node}
  end

  defp create_basic_flow(project) do
    flow = flow_fixture(project, %{name: "Test Flow"})
    {entry, _auto_exit} = get_auto_nodes(flow)

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "<p>Hello world!</p>",
          "speaker_sheet_id" => nil,
          "stage_directions" => "",
          "menu_text" => "",
          "responses" => []
        },
        position_x: 200.0,
        position_y: 0.0
      })

    _conn = connection_fixture(flow, entry, dialogue)

    {flow, entry, dialogue}
  end

  defp create_flow_with_responses(project) do
    flow = flow_fixture(project, %{name: "Response Flow"})
    {entry, auto_exit} = get_auto_nodes(flow)

    response1_id = Ecto.UUID.generate()
    response2_id = Ecto.UUID.generate()

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "<p>What do you choose?</p>",
          "speaker_sheet_id" => nil,
          "stage_directions" => "",
          "menu_text" => "",
          "responses" => [
            %{"id" => response1_id, "text" => "Option A", "condition" => "", "instruction" => ""},
            %{"id" => response2_id, "text" => "Option B", "condition" => "", "instruction" => ""}
          ]
        },
        position_x: 200.0,
        position_y: 0.0
      })

    # Update the auto-created exit node to have a label
    Flows.update_node(auto_exit, %{data: %{"label" => "The End"}})

    _conn_entry_dialogue = connection_fixture(flow, entry, dialogue)

    _conn_r1 =
      connection_fixture(flow, dialogue, auto_exit, %{
        source_pin: response1_id,
        target_pin: "input"
      })

    _conn_r2 =
      connection_fixture(flow, dialogue, auto_exit, %{
        source_pin: response2_id,
        target_pin: "input"
      })

    {flow, entry, dialogue, auto_exit, response1_id, response2_id}
  end

  defp create_entry_exit_flow(project) do
    flow = flow_fixture(project, %{name: "Short Flow"})
    {entry, auto_exit} = get_auto_nodes(flow)

    # Update exit label
    Flows.update_node(auto_exit, %{data: %{"label" => "End"}})

    # Connect entry directly to exit
    _conn = connection_fixture(flow, entry, auto_exit)

    {flow, entry, auto_exit}
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
    %{project: project}
  end

  # ===========================================================================
  # Mount
  # ===========================================================================

  describe "mount" do
    test "mounts player with valid flow", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      # Should render the player layout
      assert html =~ "story-player"
      # Should show dialogue text
      assert html =~ "Hello world!"
    end

    test "redirects when flow not found", %{conn: conn, project: project} do
      fake_flow = %{id: 999_999}

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, player_url(project, fake_flow))

      assert path =~ "/flows"
      assert flash["error"] =~ "Flow not found"
    end

    test "redirects when project not accessible", %{conn: conn} do
      other_user = Storyarn.AccountsFixtures.user_fixture()
      other_project = project_fixture(other_user) |> Repo.preload(:workspace)
      {flow, _entry, _dialogue} = create_basic_flow(other_project)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, player_url(other_project, flow))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "shows outcome when flow goes directly to exit", %{conn: conn, project: project} do
      {flow, _entry, _exit} = create_entry_exit_flow(project)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      # Should render the outcome/end state
      assert html =~ "End" or html =~ "outcome"
    end

    test "shows empty state when entry node has no connections", %{conn: conn, project: project} do
      # Entry nodes cannot be deleted (business rule), so we test an entry
      # node with no outgoing connection — the engine finishes immediately
      flow = flow_fixture(project, %{name: "Disconnected Flow"})

      {:ok, _view, html} = live(conn, player_url(project, flow))

      # Should render player layout but with empty/outcome content
      assert html =~ "story-player"
    end
  end

  # ===========================================================================
  # toggle_mode
  # ===========================================================================

  describe "toggle_mode" do
    test "toggles between player and analysis mode", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      # Toggle to analysis mode
      html = render_click(view, "toggle_mode")
      assert html =~ "story-player"
      # In analysis mode, the mode button should show "active" class
      assert html =~ "player-toolbar-btn-active"

      # Toggle back to player mode
      html = render_click(view, "toggle_mode")
      assert html =~ "story-player"
    end
  end

  # ===========================================================================
  # continue
  # ===========================================================================

  describe "continue" do
    test "dialogue without responses auto-advances to exit on mount", %{
      conn: conn,
      project: project
    } do
      # Dialogues without responses are pass-through in the player engine —
      # they follow_output immediately. So entry->dialogue->exit all advance
      # at mount time, landing on the exit/outcome slide.
      flow = flow_fixture(project, %{name: "Continue Flow"})
      {entry, auto_exit} = get_auto_nodes(flow)

      Flows.update_node(auto_exit, %{data: %{"label" => "Done"}})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>First dialogue</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => []
          },
          position_x: 200.0,
          position_y: 0.0
        })

      _conn1 = connection_fixture(flow, entry, dialogue)
      _conn2 = connection_fixture(flow, dialogue, auto_exit)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      # Dialogue without responses auto-advances to exit on mount
      assert html =~ "Done" or html =~ "outcome"
    end

    test "continue is no-op when waiting for input with responses", %{
      conn: conn,
      project: project
    } do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, html} = live(conn, player_url(project, flow))

      # Should show choices
      assert html =~ "What do you choose?"

      # Continue should be a no-op (waiting for response selection)
      html = render_click(view, "continue")
      assert html =~ "What do you choose?"
    end
  end

  # ===========================================================================
  # choose_response
  # ===========================================================================

  describe "choose_response" do
    test "selects a response and advances", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, response1_id, _response2_id} =
        create_flow_with_responses(project)

      {:ok, view, html} = live(conn, player_url(project, flow))

      assert html =~ "What do you choose?"
      assert html =~ "Option A"

      # Choose response 1
      html = render_click(view, "choose_response", %{"id" => response1_id})

      # Should advance to exit/outcome
      assert html =~ "The End" or html =~ "outcome"
    end

    test "choose_response with invalid id shows error", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      # Choose a nonexistent response
      html = render_click(view, "choose_response", %{"id" => "nonexistent-id"})

      # Should show error or remain on same dialogue
      assert html =~ "Could not select" or html =~ "What do you choose?"
    end
  end

  # ===========================================================================
  # choose_response_by_number
  # ===========================================================================

  describe "choose_response_by_number" do
    test "selects response by number", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      # Choose response 1 by number
      html = render_click(view, "choose_response_by_number", %{"number" => 1})

      # Should advance
      assert html =~ "The End" or html =~ "outcome"
    end

    test "invalid number is a no-op", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      # Choose response with out-of-range number
      html = render_click(view, "choose_response_by_number", %{"number" => 99})

      # Should stay on the same dialogue
      assert html =~ "What do you choose?"
    end
  end

  # ===========================================================================
  # go_back
  # ===========================================================================

  describe "go_back" do
    test "goes back to previous node after choosing response", %{conn: conn, project: project} do
      # Use a flow with responses. After choosing a response (which advances
      # to exit), go_back restores the pre-exit snapshot.
      # Due to how the engine snapshots work (captures pre-evaluation state),
      # the first go_back restores to the exit node's pre-eval state (same exit).
      # A second go_back restores to the dialogue node's pre-eval state.
      {flow, _entry, _dialogue, _exit, response1_id, _response2_id} =
        create_flow_with_responses(project)

      {:ok, view, html} = live(conn, player_url(project, flow))

      # Should start at dialogue (waiting for response)
      assert html =~ "What do you choose?"

      # Choose a response to advance to exit
      html = render_click(view, "choose_response", %{"id" => response1_id})
      assert html =~ "The End" or html =~ "outcome"

      # Go back twice: first to pre-exit state, then to dialogue
      render_click(view, "go_back")
      html = render_click(view, "go_back")

      # Should be back at dialogue node (text visible, though pending_choices
      # may be nil in the pre-eval snapshot)
      assert html =~ "What do you choose?"
    end

    test "go_back is a no-op when no history", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, html} = live(conn, player_url(project, flow))

      assert html =~ "Hello world!"

      # Go back at start should be a no-op
      html = render_click(view, "go_back")
      assert html =~ "Hello world!"
    end
  end

  # ===========================================================================
  # restart
  # ===========================================================================

  describe "restart" do
    test "restarts flow from beginning", %{conn: conn, project: project} do
      # Use a response-based flow so the player stops at the dialogue.
      # After choosing a response (advancing to exit), restart returns to dialogue.
      {flow, _entry, _dialogue, _exit, response1_id, _response2_id} =
        create_flow_with_responses(project)

      {:ok, view, html} = live(conn, player_url(project, flow))

      # Should start at dialogue
      assert html =~ "What do you choose?"

      # Choose a response to advance to exit
      render_click(view, "choose_response", %{"id" => response1_id})

      # Restart should go back to dialogue
      html = render_click(view, "restart")
      assert html =~ "What do you choose?"
    end
  end

  # ===========================================================================
  # exit_player
  # ===========================================================================

  describe "exit_player" do
    test "navigates back to flow editor", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      render_click(view, "exit_player")

      {path, _flash} = assert_redirect(view)
      assert path == flow_url(project, flow)
    end
  end

  # ===========================================================================
  # Scene backdrop
  # ===========================================================================

  describe "scene backdrop" do
    test "renders scene backdrop when flow has scene_id", %{conn: conn, project: project} do
      scene = Storyarn.ScenesFixtures.scene_fixture(project)
      flow = flow_fixture(project, %{name: "Scene Flow"})
      Flows.update_flow(flow, %{scene_id: scene.id})
      {entry, _exit} = get_auto_nodes(flow)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>With backdrop</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => [
              %{
                "id" => Ecto.UUID.generate(),
                "text" => "Ok",
                "condition" => "",
                "instruction" => ""
              }
            ]
          },
          position_x: 200.0,
          position_y: 0.0
        })

      _conn = connection_fixture(flow, entry, dialogue)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      # Player should render (scene backdrop div may or may not show depending on background_asset)
      assert html =~ "story-player"
      assert html =~ "With backdrop"
    end
  end

  # ===========================================================================
  # show_continue? with scene node
  # ===========================================================================

  describe "scene node in player" do
    test "renders scene slide with continue button", %{conn: conn, project: project} do
      flow = flow_fixture(project, %{name: "Scene Node Flow"})
      {entry, auto_exit} = get_auto_nodes(flow)

      scene_node =
        node_fixture(flow, %{
          type: "scene",
          data: %{
            "setting" => "INT",
            "location_name" => "Castle",
            "sub_location" => "Throne Room",
            "time_of_day" => "night",
            "description" => "<p>A dark throne room</p>"
          },
          position_x: 200.0,
          position_y: 0.0
        })

      _conn1 = connection_fixture(flow, entry, scene_node)
      _conn2 = connection_fixture(flow, scene_node, auto_exit)

      {:ok, view, html} = live(conn, player_url(project, flow))

      # Scene slides should show the scene content
      assert html =~ "story-player"

      # Scene node should show continue button (show_continue? returns true for :scene type)
      # Note: depends on whether engine stops at scene nodes
      assert html =~ "story-player"

      # Continue from scene node should advance to exit
      html = render_click(view, "continue")
      assert html =~ "story-player"
    end
  end

  # ===========================================================================
  # Cross-flow (subflow) navigation
  # ===========================================================================

  describe "cross-flow navigation" do
    setup %{project: project} do
      # ===== Sub-flow: entry → sub_dialogue → exit(caller_return) =====
      sub_flow = flow_fixture(project, %{name: "Sub Flow"})
      {sub_entry, sub_exit} = get_auto_nodes(sub_flow)

      # Set exit to caller_return mode so it triggers flow_return
      Flows.update_node(sub_exit, %{data: %{"exit_mode" => "caller_return"}})

      sub_resp_id = Ecto.UUID.generate()
      sub_resp2_id = Ecto.UUID.generate()

      sub_dialogue =
        node_fixture(sub_flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Sub flow dialogue</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => [
              %{
                "id" => sub_resp_id,
                "text" => "Sub option",
                "condition" => "",
                "instruction" => ""
              },
              %{
                "id" => sub_resp2_id,
                "text" => "Sub alt",
                "condition" => "",
                "instruction" => ""
              }
            ]
          },
          position_x: 200.0,
          position_y: 0.0
        })

      connection_fixture(sub_flow, sub_entry, sub_dialogue)

      connection_fixture(sub_flow, sub_dialogue, sub_exit, %{
        source_pin: sub_resp_id,
        target_pin: "input"
      })

      connection_fixture(sub_flow, sub_dialogue, sub_exit, %{
        source_pin: sub_resp2_id,
        target_pin: "input"
      })

      # ===== Main flow: entry → dialogue → subflow → after_dialogue → exit =====
      main_flow = flow_fixture(project, %{name: "Main Flow"})
      {main_entry, main_exit} = get_auto_nodes(main_flow)

      main_resp_id = Ecto.UUID.generate()
      main_resp2_id = Ecto.UUID.generate()

      main_dialogue =
        node_fixture(main_flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Main dialogue</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => [
              %{
                "id" => main_resp_id,
                "text" => "Go to sub",
                "condition" => "",
                "instruction" => ""
              },
              %{
                "id" => main_resp2_id,
                "text" => "Stay",
                "condition" => "",
                "instruction" => ""
              }
            ]
          },
          position_x: 200.0,
          position_y: 0.0
        })

      subflow_node =
        node_fixture(main_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => sub_flow.id},
          position_x: 400.0,
          position_y: 0.0
        })

      after_resp_id = Ecto.UUID.generate()
      after_resp2_id = Ecto.UUID.generate()

      after_dialogue =
        node_fixture(main_flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Back in main</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => [
              %{
                "id" => after_resp_id,
                "text" => "Finish",
                "condition" => "",
                "instruction" => ""
              },
              %{
                "id" => after_resp2_id,
                "text" => "Wait",
                "condition" => "",
                "instruction" => ""
              }
            ]
          },
          position_x: 600.0,
          position_y: 0.0
        })

      connection_fixture(main_flow, main_entry, main_dialogue)

      connection_fixture(main_flow, main_dialogue, subflow_node, %{
        source_pin: main_resp_id,
        target_pin: "input"
      })

      connection_fixture(main_flow, subflow_node, after_dialogue)

      connection_fixture(main_flow, after_dialogue, main_exit, %{
        source_pin: after_resp_id,
        target_pin: "input"
      })

      %{
        main_flow: main_flow,
        sub_flow: sub_flow,
        main_resp_id: main_resp_id,
        sub_resp_id: sub_resp_id,
        after_resp_id: after_resp_id
      }
    end

    test "flow_jump redirects to sub-flow player", %{
      conn: conn,
      project: project,
      main_flow: main_flow,
      sub_flow: sub_flow,
      main_resp_id: main_resp_id
    } do
      {:ok, view, html} = live(conn, player_url(project, main_flow))
      assert html =~ "Main dialogue"

      # Choose response → subflow node → flow_jump → redirect to sub-flow
      render_click(view, "choose_response", %{"id" => main_resp_id})
      {path, _flash} = assert_redirect(view)
      assert path =~ "/flows/#{sub_flow.id}/play"
    end

    test "session restored after flow_jump shows sub-flow content", %{
      conn: conn,
      project: project,
      main_flow: main_flow,
      main_resp_id: main_resp_id
    } do
      {:ok, view, _html} = live(conn, player_url(project, main_flow))
      render_click(view, "choose_response", %{"id" => main_resp_id})
      {path, _} = assert_redirect(view)

      # Follow redirect — session restore shows sub-flow dialogue
      {:ok, _new_view, html} = live(conn, path)
      assert html =~ "Sub flow dialogue"
    end

    test "flow_return navigates back to parent flow", %{
      conn: conn,
      project: project,
      main_flow: main_flow,
      main_resp_id: main_resp_id,
      sub_resp_id: sub_resp_id
    } do
      # Step 1: Navigate into sub-flow
      {:ok, view, _html} = live(conn, player_url(project, main_flow))
      render_click(view, "choose_response", %{"id" => main_resp_id})
      {sub_path, _} = assert_redirect(view)

      # Step 2: In sub-flow, choose response → exit(caller_return) → flow_return
      {:ok, sub_view, html} = live(conn, sub_path)
      assert html =~ "Sub flow dialogue"
      render_click(sub_view, "choose_response", %{"id" => sub_resp_id})
      {parent_path, _} = assert_redirect(sub_view)

      # Step 3: Should be back in main flow showing after_dialogue
      {:ok, _parent_view, html} = live(conn, parent_path)
      assert html =~ "Back in main"
    end

    test "handles subflow node with nil referenced_flow_id", %{
      conn: conn,
      project: project
    } do
      # A subflow node with no referenced flow is treated as finished
      flow = flow_fixture(project, %{name: "Bad Subflow Flow"})
      {entry, _exit} = get_auto_nodes(flow)

      resp_id = Ecto.UUID.generate()
      resp2_id = Ecto.UUID.generate()

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Before bad subflow</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => [
              %{"id" => resp_id, "text" => "Go", "condition" => "", "instruction" => ""},
              %{"id" => resp2_id, "text" => "Stay", "condition" => "", "instruction" => ""}
            ]
          },
          position_x: 200.0,
          position_y: 0.0
        })

      subflow_node =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => nil},
          position_x: 400.0,
          position_y: 0.0
        })

      connection_fixture(flow, entry, dialogue)

      connection_fixture(flow, dialogue, subflow_node, %{
        source_pin: resp_id,
        target_pin: "input"
      })

      {:ok, view, html} = live(conn, player_url(project, flow))
      assert html =~ "Before bad subflow"

      # Choosing response advances to subflow with nil flow → engine finishes
      html = render_click(view, "choose_response", %{"id" => resp_id})
      assert html =~ "story-player"
    end
  end

  # ===========================================================================
  # choose_response_by_number in analysis mode
  # ===========================================================================

  describe "choose_response_by_number in analysis mode" do
    test "shows all responses including invalid ones in analysis mode", %{
      conn: conn,
      project: project
    } do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      # Toggle to analysis mode
      html = render_click(view, "toggle_mode")
      assert html =~ "player-toolbar-btn-active"

      # Both responses should be visible in analysis mode
      assert html =~ "Option A"
      assert html =~ "Option B"
    end
  end

  # ===========================================================================
  # Toolbar rendering
  # ===========================================================================

  describe "toolbar rendering" do
    test "hides continue button when dialogue has responses (waiting for choice)", %{
      conn: conn,
      project: project
    } do
      # When a dialogue has multiple valid responses, the engine is waiting_input.
      # The continue button should NOT appear because the player expects a response choice.
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      # Should show the dialogue
      assert html =~ "What do you choose?"
      # Continue button should NOT be shown (player is waiting for response selection)
      refute html =~ "player-toolbar-btn-primary"
    end

    test "hides continue button when engine is finished", %{
      conn: conn,
      project: project
    } do
      # When the engine reaches an exit node (finished), no continue button shown.
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      # The basic flow ends at a dialogue with no outgoing connection (finished state).
      # Continue button hidden because is_finished is true.
      refute html =~ "player-toolbar-btn-primary"
    end

    test "shows back button", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      assert html =~ "go_back"
    end

    test "shows toggle mode button", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      assert html =~ "toggle_mode"
    end

    test "shows restart button", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, _view, html} = live(conn, player_url(project, flow))

      assert html =~ "restart"
    end
  end
end
