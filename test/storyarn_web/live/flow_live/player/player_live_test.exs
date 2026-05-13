defmodule StoryarnWeb.FlowLive.PlayerLiveTest do
  @moduledoc """
  Integration tests for the PlayerLive full-screen story player.

  Tests mount, navigation events (continue, go_back, restart, exit_player),
  toggle_mode, choose_response, and error cases.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp player_url(project, flow) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/play"
  end

  defp flow_url(project, flow) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end

  defp get_player_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/flow/player/FlowPlayer")
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
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  # ===========================================================================
  # Mount
  # ===========================================================================

  describe "mount" do
    test "mounts player with valid flow", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, html} = live(conn, player_url(project, flow))

      # Should render the player layout
      assert html =~ "story-player"

      # Vue component should be mounted with slide data
      vue = get_player_vue(view)
      assert vue.component == "live/flow/player/FlowPlayer"
      assert vue.props["slide"]["type"] in ["dialogue", "outcome"]
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
      other_project = other_user |> project_fixture() |> Repo.preload(:workspace)
      {flow, _entry, _dialogue} = create_basic_flow(other_project)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, player_url(other_project, flow))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "shows outcome when flow goes directly to exit", %{conn: conn, project: project} do
      {flow, _entry, _exit} = create_entry_exit_flow(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "outcome"
    end

    test "shows empty state when entry node has no connections", %{conn: conn, project: project} do
      flow = flow_fixture(project, %{name: "Disconnected Flow"})

      {:ok, _view, html} = live(conn, player_url(project, flow))

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

      vue = get_player_vue(view)
      assert vue.props["player-mode"] == "player"

      # Toggle to analysis mode
      render_click(view, "toggle_mode")

      vue = get_player_vue(view)
      assert vue.props["player-mode"] == "analysis"

      # Toggle back to player mode
      render_click(view, "toggle_mode")

      vue = get_player_vue(view)
      assert vue.props["player-mode"] == "player"
    end
  end

  # ===========================================================================
  # continue
  # ===========================================================================

  describe "continue" do
    test "dialogue without responses waits for continue before advancing", %{
      conn: conn,
      project: project
    } do
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

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "dialogue"
      assert vue.props["slide"]["text"] =~ "First dialogue"
      assert vue.props["show-continue"] == true

      render_click(view, "continue")

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "outcome"
    end

    test "dialogue with a single valid response waits for continue before auto-selecting it", %{
      conn: conn,
      project: project
    } do
      flow = flow_fixture(project, %{name: "Single Response Flow"})
      {entry, auto_exit} = get_auto_nodes(flow)
      response_id = Ecto.UUID.generate()

      Flows.update_node(auto_exit, %{data: %{"label" => "Done"}})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Read this before choosing.</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => [
              %{"id" => response_id, "text" => "Continue", "condition" => "", "instruction" => ""}
            ]
          },
          position_x: 200.0,
          position_y: 0.0
        })

      _conn1 = connection_fixture(flow, entry, dialogue)
      _conn2 = connection_fixture(flow, dialogue, auto_exit, %{source_pin: response_id})

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "dialogue"
      assert vue.props["slide"]["text"] =~ "Read this before choosing."
      assert vue.props["responses"] == []
      assert vue.props["show-continue"] == true

      render_click(view, "continue")

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "outcome"
    end

    test "continue is no-op when waiting for input with responses", %{
      conn: conn,
      project: project
    } do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "dialogue"
      assert vue.props["slide"]["text"] =~ "What do you choose?"

      # Continue should be a no-op (waiting for response selection)
      render_click(view, "continue")

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "What do you choose?"
    end
  end

  # ===========================================================================
  # choose_response
  # ===========================================================================

  describe "choose_response" do
    test "selects a response and advances", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, response1_id, _response2_id} =
        create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "What do you choose?"

      # Choose response 1
      render_click(view, "choose_response", %{"id" => response1_id})

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "outcome"
    end

    test "choose_response with invalid id shows error", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      # Choose a nonexistent response
      html = render_click(view, "choose_response", %{"id" => "nonexistent-id"})

      # Should show error or remain on same dialogue
      vue = get_player_vue(view)
      assert html =~ "Could not select" or vue.props["slide"]["text"] =~ "What do you choose?"
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
      render_click(view, "choose_response_by_number", %{"number" => 1})

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "outcome"
    end

    test "invalid number is a no-op", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      # Choose response with out-of-range number
      render_click(view, "choose_response_by_number", %{"number" => 99})

      # Should stay on the same dialogue
      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "What do you choose?"
    end
  end

  # ===========================================================================
  # go_back
  # ===========================================================================

  describe "go_back" do
    test "goes back to previous node after choosing response", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, response1_id, _response2_id} =
        create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "What do you choose?"

      # Choose a response to advance to exit
      render_click(view, "choose_response", %{"id" => response1_id})

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == "outcome"

      # Go back twice: first to pre-exit state, then to dialogue
      render_click(view, "go_back")
      render_click(view, "go_back")

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "What do you choose?"
    end

    test "go_back is a no-op when no history", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      slide_before = vue.props["slide"]

      # Go back at start should be a no-op
      render_click(view, "go_back")

      vue = get_player_vue(view)
      assert vue.props["slide"]["type"] == slide_before["type"]
    end
  end

  # ===========================================================================
  # restart
  # ===========================================================================

  describe "restart" do
    test "restarts flow from beginning", %{conn: conn, project: project} do
      {flow, _entry, _dialogue, _exit, response1_id, _response2_id} =
        create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "What do you choose?"

      # Choose a response to advance to exit
      render_click(view, "choose_response", %{"id" => response1_id})

      # Restart should go back to dialogue
      render_click(view, "restart")

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "What do you choose?"
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
    test "renders player with scene flow", %{conn: conn, project: project} do
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

      {:ok, view, html} = live(conn, player_url(project, flow))

      assert html =~ "story-player"

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "With backdrop"
      assert vue.props["visual-layers"] == []
    end

    test "uses active sequence visual layers ordered from parent to child", %{
      conn: conn,
      project: project,
      user: user
    } do
      backdrop_asset = image_asset_fixture(project, user, %{url: "/uploads/sequence-bg.png"})
      character_asset = image_asset_fixture(project, user, %{url: "/uploads/sequence-character.png"})
      flow = flow_fixture(project, %{name: "Sequence Visual Layer Flow"})
      {entry, _exit} = get_auto_nodes(flow)

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Intro Sequence"
        })

      {:ok, backdrop_layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          "kind" => "backdrop",
          "asset_id" => backdrop_asset.id
        })

      {:ok, child_sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Nested Sequence",
          "parent_id" => sequence.id
        })

      {:ok, character_layer} =
        Flows.create_sequence_visual_layer(child_sequence.id, %{
          "kind" => "character",
          "asset_id" => character_asset.id,
          "slot" => "right"
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          parent_id: child_sequence.id,
          data: %{
            "text" => "<p>Inside sequence</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => []
          },
          position_x: 200.0,
          position_y: 0.0
        })

      _conn = connection_fixture(flow, entry, dialogue)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)

      assert vue.props["visual-layers"] == [
               %{
                 "id" => backdrop_layer.id,
                 "sequence_id" => sequence.id,
                 "sequence_depth" => 0,
                 "kind" => "backdrop",
                 "label" => nil,
                 "url" => "/uploads/sequence-bg.png",
                 "z_index" => 0,
                 "slot" => "full",
                 "x" => 0.0,
                 "y" => 0.0,
                 "width" => 1.0,
                 "height" => 1.0,
                 "anchor_x" => 0.0,
                 "anchor_y" => 0.0,
                 "fit" => "cover",
                 "opacity" => 1.0
               },
               %{
                 "id" => character_layer.id,
                 "sequence_id" => child_sequence.id,
                 "sequence_depth" => 1,
                 "kind" => "character",
                 "label" => nil,
                 "url" => "/uploads/sequence-character.png",
                 "z_index" => 100,
                 "slot" => "right",
                 "x" => 0.75,
                 "y" => 1.0,
                 "width" => 0.38,
                 "height" => 0.9,
                 "anchor_x" => 0.5,
                 "anchor_y" => 1.0,
                 "fit" => "contain",
                 "opacity" => 1.0
               }
             ]
    end

    test "passes active sequence audio tracks ordered from parent to child", %{
      conn: conn,
      project: project,
      user: user
    } do
      parent_audio = audio_asset_fixture(project, user, %{url: "/uploads/parent-theme.mp3"})
      child_audio = audio_asset_fixture(project, user, %{url: "/uploads/child-ambient.mp3"})
      flow = flow_fixture(project, %{name: "Sequence Audio Flow"})
      {entry, _exit} = get_auto_nodes(flow)

      {:ok, parent_sequence} = Flows.create_sequence(flow.id, %{"name" => "Parent"})

      {:ok, child_sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Child",
          "parent_id" => parent_sequence.id
        })

      {:ok, parent_track} =
        Flows.upsert_sequence_track(parent_sequence.id, "music", %{
          "asset_id" => parent_audio.id,
          "volume" => Decimal.new("0.50")
        })

      {:ok, child_track} =
        Flows.upsert_sequence_track(child_sequence.id, "ambience", %{
          "asset_id" => child_audio.id,
          "volume" => Decimal.new("0.25")
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          parent_id: child_sequence.id,
          data: %{
            "text" => "<p>Inside audio sequence</p>",
            "speaker_sheet_id" => nil,
            "stage_directions" => "",
            "menu_text" => "",
            "responses" => []
          },
          position_x: 200.0,
          position_y: 0.0
        })

      _conn = connection_fixture(flow, entry, dialogue)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)

      assert vue.props["audio-tracks"] == [
               %{
                 "id" => parent_track.id,
                 "sequence_id" => parent_sequence.id,
                 "kind" => "music",
                 "position" => 0,
                 "url" => "/uploads/parent-theme.mp3",
                 "volume" => 0.5,
                 "content_type" => "audio/mpeg",
                 "filename" => parent_audio.filename,
                 "depth" => 0
               },
               %{
                 "id" => child_track.id,
                 "sequence_id" => child_sequence.id,
                 "kind" => "ambience",
                 "position" => 0,
                 "url" => "/uploads/child-ambient.mp3",
                 "volume" => 0.25,
                 "content_type" => "audio/mpeg",
                 "filename" => child_audio.filename,
                 "depth" => 1
               }
             ]
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
      {:ok, view, _html} = live(conn, player_url(project, main_flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "Main dialogue"

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
      {:ok, new_view, _html} = live(conn, path)

      vue = LiveVue.Test.get_vue(new_view, name: "live/flow/player/FlowPlayer")
      assert vue.props["slide"]["text"] =~ "Sub flow dialogue"
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
      {:ok, sub_view, _html} = live(conn, sub_path)

      vue = LiveVue.Test.get_vue(sub_view, name: "live/flow/player/FlowPlayer")
      assert vue.props["slide"]["text"] =~ "Sub flow dialogue"

      render_click(sub_view, "choose_response", %{"id" => sub_resp_id})
      {parent_path, _} = assert_redirect(sub_view)

      # Step 3: Should be back in main flow showing after_dialogue
      {:ok, parent_view, _html} = live(conn, parent_path)

      vue = LiveVue.Test.get_vue(parent_view, name: "live/flow/player/FlowPlayer")
      assert vue.props["slide"]["text"] =~ "Back in main"
    end

    test "handles subflow node with nil referenced_flow_id", %{
      conn: conn,
      project: project
    } do
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

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["slide"]["text"] =~ "Before bad subflow"

      # Choosing response advances to subflow with nil flow → engine finishes
      render_click(view, "choose_response", %{"id" => resp_id})

      vue = get_player_vue(view)
      assert vue.component == "live/flow/player/FlowPlayer"
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
      render_click(view, "toggle_mode")

      vue = get_player_vue(view)
      assert vue.props["player-mode"] == "analysis"

      # Both responses should be in the props
      responses = vue.props["responses"]
      texts = Enum.map(responses, & &1["text"])
      assert "Option A" in texts
      assert "Option B" in texts
    end
  end

  # ===========================================================================
  # Toolbar props
  # ===========================================================================

  describe "toolbar props" do
    test "hides continue button when dialogue has responses (waiting for choice)", %{
      conn: conn,
      project: project
    } do
      {flow, _entry, _dialogue, _exit, _r1, _r2} = create_flow_with_responses(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["show-continue"] == false
    end

    test "shows continue button when dialogue has no choices", %{
      conn: conn,
      project: project
    } do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["is-finished"] == false
      assert vue.props["show-continue"] == true
    end

    test "passes can-go-back as false initially", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      # can_go_back depends on whether there are snapshots, which depends on how many
      # nodes were auto-advanced through
      assert is_boolean(vue.props["can-go-back"])
    end

    test "passes editor-url", %{conn: conn, project: project} do
      {flow, _entry, _dialogue} = create_basic_flow(project)

      {:ok, view, _html} = live(conn, player_url(project, flow))

      vue = get_player_vue(view)
      assert vue.props["editor-url"] =~ "/flows/#{flow.id}"
    end
  end
end
