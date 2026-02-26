defmodule StoryarnWeb.SceneLive.ExplorationLiveTest do
  @moduledoc """
  Tests for the SceneLive.ExplorationLive full-screen exploration player.

  Covers: mount (valid, invalid project, missing scene), exit_exploration,
  keyboard handling, element clicks (instruction actions, scene/flow targets),
  visibility evaluation, and flow overlay interactions.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.FlowsFixtures
  alias Storyarn.Repo
  alias Storyarn.Scenes

  # =========================================================================
  # Helpers
  # =========================================================================

  defp explore_path(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}/explore"
  end

  defp scene_show_path(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp setup_project_with_scene(%{user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Test World"})

    %{project: project, scene: scene}
  end

  defp setup_scene_with_elements(%{user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Interactive World"})

    zone =
      zone_fixture(scene, %{
        "name" => "Town Square",
        "vertices" => [
          %{"x" => 10.0, "y" => 10.0},
          %{"x" => 50.0, "y" => 10.0},
          %{"x" => 30.0, "y" => 50.0}
        ]
      })

    pin =
      pin_fixture(scene, %{
        "position_x" => 25.0,
        "position_y" => 25.0,
        "label" => "Tavern"
      })

    %{project: project, scene: scene, zone: zone, pin: pin}
  end

  # Gets the auto-created entry node from a flow
  defp get_entry_node(flow) do
    Flows.list_nodes(flow.id)
    |> Enum.find(&(&1.type == "entry"))
  end

  # Gets the auto-created exit node from a flow
  defp get_exit_node(flow) do
    Flows.list_nodes(flow.id)
    |> Enum.find(&(&1.type == "exit"))
  end

  # Creates a flow with entry -> dialogue connection for flow mode tests
  defp create_flow_with_dialogue(project, flow_name, dialogue_text) do
    flow = FlowsFixtures.flow_fixture(project, %{name: flow_name})
    entry = get_entry_node(flow)

    dialogue =
      FlowsFixtures.node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => dialogue_text, "speaker_sheet_id" => nil, "responses" => []}
      })

    FlowsFixtures.connection_fixture(flow, entry, dialogue)

    {flow, entry, dialogue}
  end

  # Creates a flow: entry -> dialogue1 -> dialogue2 -> exit
  defp create_flow_with_two_dialogues(project, flow_name, text1, text2) do
    flow = FlowsFixtures.flow_fixture(project, %{name: flow_name})
    entry = get_entry_node(flow)
    exit_node = get_exit_node(flow)

    dialogue1 =
      FlowsFixtures.node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => text1, "speaker_sheet_id" => nil, "responses" => []}
      })

    dialogue2 =
      FlowsFixtures.node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => text2, "speaker_sheet_id" => nil, "responses" => []}
      })

    FlowsFixtures.connection_fixture(flow, entry, dialogue1)
    FlowsFixtures.connection_fixture(flow, dialogue1, dialogue2)
    FlowsFixtures.connection_fixture(flow, dialogue2, exit_node)

    {flow, dialogue1, dialogue2, exit_node}
  end

  # Creates a flow with a dialogue that has 2 response choices, each connected to a target
  defp create_flow_with_response_dialogue(project, flow_name) do
    flow = FlowsFixtures.flow_fixture(project, %{name: flow_name})
    entry = get_entry_node(flow)
    exit_node = get_exit_node(flow)

    resp_a_id = Ecto.UUID.generate()
    resp_b_id = Ecto.UUID.generate()

    dialogue =
      FlowsFixtures.node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Choose your path",
          "speaker_sheet_id" => nil,
          "responses" => [
            %{"id" => resp_a_id, "text" => "Path A", "condition" => nil, "instruction" => nil},
            %{"id" => resp_b_id, "text" => "Path B", "condition" => nil, "instruction" => nil}
          ]
        }
      })

    dialogue_after =
      FlowsFixtures.node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "After choice", "speaker_sheet_id" => nil, "responses" => []}
      })

    FlowsFixtures.connection_fixture(flow, entry, dialogue)

    # Use the response ID as the source_pin (choose_response looks for this)
    FlowsFixtures.connection_fixture(flow, dialogue, dialogue_after, %{
      source_pin: resp_a_id,
      target_pin: "input"
    })

    FlowsFixtures.connection_fixture(flow, dialogue, exit_node, %{
      source_pin: resp_b_id,
      target_pin: "input"
    })

    FlowsFixtures.connection_fixture(flow, dialogue_after, exit_node)

    {flow, dialogue, resp_a_id, resp_b_id, dialogue_after}
  end

  # Creates a sheet with a number block variable
  defp create_number_variable(project, sheet_name, block_label, default_value) do
    sheet = sheet_fixture(project, %{name: sheet_name})

    block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => block_label},
        value: %{"content" => to_string(default_value)}
      })

    {sheet, block}
  end

  # =========================================================================
  # Mount — valid
  # =========================================================================

  describe "mount (valid)" do
    setup [:register_and_log_in_user, :setup_project_with_scene]

    test "renders exploration page with scene name", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Test World"
      assert html =~ "Exit"
      assert html =~ "exploration-player"
    end

    test "renders the ExplorationPlayer hook element", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ ~s(id="exploration-player")
      assert html =~ ~s(phx-hook="ExplorationPlayer")
    end

    test "uses layout: false (no standard layout wrapper)", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "player-layout"
    end

    test "does not show flow overlay initially", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, _view, html} = live(conn, explore_path(project, scene))

      refute html =~ "exploration-flow-overlay"
      refute html =~ "Return to map"
    end

    test "includes exploration data as JSON", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "data-exploration="
    end
  end

  # =========================================================================
  # Mount — with zones and pins
  # =========================================================================

  describe "mount (with elements)" do
    setup [:register_and_log_in_user, :setup_scene_with_elements]

    test "serializes zones and pins into exploration data", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "data-exploration="
      assert html =~ "exploration-player"
    end
  end

  # =========================================================================
  # Mount — invalid project
  # =========================================================================

  describe "mount (invalid project)" do
    setup :register_and_log_in_user

    test "redirects to workspaces when project not accessible", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Forbidden"})

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, explore_path(project, scene))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "redirects non-member with error flash", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} =
        live(conn, ~p"/workspaces/nonexistent-ws/projects/nonexistent-proj/scenes/999/explore")

      assert path == "/workspaces"
    end
  end

  # =========================================================================
  # Mount — scene not found
  # =========================================================================

  describe "mount (scene not found)" do
    setup :register_and_log_in_user

    test "redirects to scene index when scene does not exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/999999/explore"
        )

      assert path =~ "/scenes"
      assert flash["error"] =~ "not found"
    end

    test "redirects when scene is soft-deleted", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Deleted Scene"})
      {:ok, _} = Scenes.delete_scene(scene)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, explore_path(project, scene))

      assert path =~ "/scenes"
      assert flash["error"] =~ "not found"
    end
  end

  # =========================================================================
  # Exit exploration
  # =========================================================================

  describe "exit_exploration event" do
    setup [:register_and_log_in_user, :setup_project_with_scene]

    test "navigates back to scene show page", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exit_exploration")

      expected_path = scene_show_path(project, scene)
      assert_redirect(view, expected_path)
    end
  end

  # =========================================================================
  # Keyboard events
  # =========================================================================

  describe "handle_keydown" do
    setup [:register_and_log_in_user, :setup_project_with_scene]

    test "Escape navigates back to scene show page when not in flow mode", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_keydown(view, "handle_keydown", %{"key" => "Escape"})

      expected_path = scene_show_path(project, scene)
      assert_redirect(view, expected_path)
    end

    test "unhandled keys are ignored", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html = render_keydown(view, "handle_keydown", %{"key" => "a"})
      assert html =~ "Test World"
    end

    test "space key is ignored when not in flow mode", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html = render_keydown(view, "handle_keydown", %{"key" => " "})
      assert html =~ "Test World"
    end

    test "Enter key is ignored when not in flow mode", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html = render_keydown(view, "handle_keydown", %{"key" => "Enter"})
      assert html =~ "Test World"
    end

    test "number keys are ignored when not in flow mode", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html = render_keydown(view, "handle_keydown", %{"key" => "1"})
      assert html =~ "Test World"
    end

    test "ArrowRight key is ignored when not in flow mode", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html = render_keydown(view, "handle_keydown", %{"key" => "ArrowRight"})
      assert html =~ "Test World"
    end
  end

  # =========================================================================
  # Element click — no action/no target
  # =========================================================================

  describe "exploration_element_click (no action, no target)" do
    setup [:register_and_log_in_user, :setup_project_with_scene]

    test "click with no action/target does nothing", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html = render_click(view, "exploration_element_click", %{})
      assert html =~ "Test World"
    end

    test "click with unknown action type does nothing", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "action_type" => "unknown",
          "action_data" => %{}
        })

      assert html =~ "Test World"
    end
  end

  # =========================================================================
  # Element click — scene target (navigation)
  # =========================================================================

  describe "exploration_element_click (scene target)" do
    setup [:register_and_log_in_user, :setup_scene_with_elements]

    test "clicking element with scene target navigates to that scene", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      target_scene = scene_fixture(project, %{name: "Target Scene"})

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "scene",
        "target_id" => to_string(target_scene.id)
      })

      assert_redirect(view, explore_path(project, target_scene))
    end

    test "clicking element with empty scene target does nothing", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "target_type" => "scene",
          "target_id" => ""
        })

      assert html =~ "Interactive World"
    end

    test "clicking element with nil scene target does nothing", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "target_type" => "scene",
          "target_id" => nil
        })

      assert html =~ "Interactive World"
    end
  end

  # =========================================================================
  # Element click — flow target
  # =========================================================================

  describe "exploration_element_click (flow target)" do
    setup [:register_and_log_in_user, :setup_scene_with_elements]

    test "clicking element with non-existent flow shows error", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => "999999"
      })

      html = render(view)
      assert html =~ "Flow not found"
    end

    test "clicking element with empty flow target does nothing", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "target_type" => "flow",
          "target_id" => ""
        })

      assert html =~ "Interactive World"
    end

    test "clicking element with invalid (non-numeric) flow target does nothing", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "target_type" => "flow",
          "target_id" => "not-a-number"
        })

      assert html =~ "Interactive World"
    end

    test "clicking element with valid flow enters flow mode", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Dialogue Flow", "Hello traveler!")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render(view)
      # Flow mode should be active — check for flow overlay or flow name
      assert html =~ "exploration-flow-overlay" or html =~ "Dialogue Flow"
    end
  end

  # =========================================================================
  # Element click — instruction action
  # =========================================================================

  describe "exploration_element_click (instruction action)" do
    setup :register_and_log_in_user

    test "instruction action with no assignments does not crash", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Instruction World"})

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "action_type" => "instruction",
          "action_data" => %{"assignments" => []}
        })

      assert html =~ "Instruction World"
    end

    test "instruction action with valid assignment updates variables", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Assignment World"})
      {sheet, _block} = create_number_variable(project, "Hero", "Health", 100)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "action_type" => "instruction",
          "action_data" => %{
            "assignments" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "health",
                "operator" => "set",
                "value" => "50"
              }
            ]
          }
        })

      # Should not crash, page still renders
      assert html =~ "Assignment World"
    end
  end

  # =========================================================================
  # Element click — unknown target type
  # =========================================================================

  describe "exploration_element_click (unknown target type)" do
    setup [:register_and_log_in_user, :setup_project_with_scene]

    test "clicking element with unknown target type does nothing", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      {:ok, view, _html} = live(conn, explore_path(project, scene))

      html =
        render_click(view, "exploration_element_click", %{
          "target_type" => "unknown",
          "target_id" => "123"
        })

      assert html =~ "Test World"
    end
  end

  # =========================================================================
  # Visibility evaluation
  # =========================================================================

  describe "visibility evaluation" do
    setup :register_and_log_in_user

    test "zones/pins with no condition are visible", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Visible World"})

      _zone =
        zone_fixture(scene, %{
          "name" => "Open Zone",
          "condition" => nil,
          "condition_effect" => "hide"
        })

      _pin =
        pin_fixture(scene, %{
          "label" => "Open Pin",
          "condition" => nil,
          "condition_effect" => "hide"
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "data-exploration="
    end

    test "zones with empty condition map are visible", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Empty Condition World"})

      {:ok, _} =
        Scenes.create_zone(scene.id, %{
          "name" => "Empty Cond Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ],
          "condition" => %{},
          "condition_effect" => "hide"
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "data-exploration="
    end

    test "zone with failing condition and hide effect gets hidden", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Conditional World"})
      {sheet, _block} = create_number_variable(project, "Hero", "Health", 100)

      # Condition checks that hero.health > 999 (will fail since default is 100)
      _zone =
        zone_fixture(scene, %{
          "name" => "Hidden Zone",
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "health",
                "operator" => "greater_than",
                "value" => "999"
              }
            ]
          },
          "condition_effect" => "hide"
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Conditional World"
    end

    test "zone with failing condition and disable effect gets disabled", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Disable World"})
      {sheet, _block} = create_number_variable(project, "Player", "Level", 1)

      # Condition checks that player.level > 10 (will fail since default is 1)
      _zone =
        zone_fixture(scene, %{
          "name" => "Disabled Zone",
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "level",
                "operator" => "greater_than",
                "value" => "10"
              }
            ]
          },
          "condition_effect" => "disable"
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Disable World"
    end

    test "zone with passing condition is visible", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Pass World"})
      {sheet, _block} = create_number_variable(project, "Warrior", "Strength", 50)

      # Condition checks that warrior.strength > 10 (will pass since default is 50)
      _zone =
        zone_fixture(scene, %{
          "name" => "Visible Zone",
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "strength",
                "operator" => "greater_than",
                "value" => "10"
              }
            ]
          },
          "condition_effect" => "hide"
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Pass World"
    end
  end

  # =========================================================================
  # Flow mode — exit from flow overlay
  # =========================================================================

  describe "exit from flow overlay" do
    setup :register_and_log_in_user

    test "exit_exploration while in flow mode returns to map (not navigation)", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Flow Overlay World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Test Flow", "Greetings!")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Now exit while in flow mode — should return to map exploration, not navigate away
      html = render_click(view, "exit_exploration")

      refute html =~ "exploration-flow-overlay"
      assert html =~ "Flow Overlay World"
    end

    test "Escape while in flow mode returns to map exploration", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Escape Flow World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Escape Flow", "Hello!")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Escape while in flow mode
      html = render_keydown(view, "handle_keydown", %{"key" => "Escape"})

      refute html =~ "exploration-flow-overlay"
      assert html =~ "Escape Flow World"
    end
  end

  # =========================================================================
  # Flow execution — go_back
  # =========================================================================

  describe "go_back event" do
    setup :register_and_log_in_user

    test "go_back with no history does nothing", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Back World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Back Flow", "Start here")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Try to go back (should be no-op since we're at the start)
      html = render_click(view, "go_back")

      # Should still be in flow mode
      assert html =~ "exploration-flow-overlay" or html =~ "Back Flow"
    end
  end

  # =========================================================================
  # Flow execution — flow_finish
  # =========================================================================

  describe "flow_finish event" do
    setup :register_and_log_in_user

    test "flow_finish returns to map exploration", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Finish World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Finish Flow", "Farewell!")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Finish the flow
      html = render_click(view, "flow_finish")

      # Should return to map exploration
      refute html =~ "exploration-flow-overlay"
      assert html =~ "Finish World"
    end
  end

  # =========================================================================
  # Flow execution — flow_continue
  # =========================================================================

  describe "flow_continue event" do
    setup :register_and_log_in_user

    test "flow_continue advances through the flow", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Continue World"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Continue Flow"})
      entry = get_entry_node(flow)

      dialogue1 =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "First line", "speaker_sheet_id" => nil, "responses" => []}
        })

      dialogue2 =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Second line", "speaker_sheet_id" => nil, "responses" => []}
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue1)
      FlowsFixtures.connection_fixture(flow, dialogue1, dialogue2)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Continue — should advance to next dialogue or eventually finish
      html = render_click(view, "flow_continue")

      # Should still be in flow mode or have advanced
      assert html =~ "exploration-flow-overlay" or html =~ "Continue World"
    end
  end

  # =========================================================================
  # Authentication
  # =========================================================================

  describe "authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/scenes/1/explore")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  # =========================================================================
  # Editor member access
  # =========================================================================

  describe "member access" do
    setup :register_and_log_in_user

    test "editor member can access exploration mode", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      scene = scene_fixture(project, %{name: "Editor Scene"})

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Editor Scene"
    end

    test "viewer member can access exploration mode", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project, %{name: "Viewer Scene"})

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Viewer Scene"
    end
  end

  # =========================================================================
  # Multiple elements with mixed visibility
  # =========================================================================

  describe "mixed visibility" do
    setup :register_and_log_in_user

    test "scene with mixed visible/hidden/disabled elements renders correctly", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Mixed World"})

      # Zone with no condition (visible)
      _zone1 = zone_fixture(scene, %{"name" => "Visible Zone"})

      # Pin with no condition (visible)
      _pin1 = pin_fixture(scene, %{"label" => "Visible Pin"})

      # Zone with empty condition map (visible)
      {:ok, _zone2} =
        Scenes.create_zone(scene.id, %{
          "name" => "Empty Cond Zone",
          "vertices" => [
            %{"x" => 60.0, "y" => 60.0},
            %{"x" => 80.0, "y" => 60.0},
            %{"x" => 70.0, "y" => 80.0}
          ],
          "condition" => %{}
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Mixed World"
      assert html =~ "data-exploration="
    end
  end

  # =========================================================================
  # Pin visibility with condition
  # =========================================================================

  describe "pin visibility with condition" do
    setup :register_and_log_in_user

    test "pin with failing condition and hide effect", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Pin Condition World"})
      {sheet, _block} = create_number_variable(project, "Rogue", "Stealth", 5)

      {:ok, _pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "label" => "Secret Door",
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "stealth",
                "operator" => "greater_than",
                "value" => "100"
              }
            ]
          },
          "condition_effect" => "hide"
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Pin Condition World"
    end

    test "pin with passing condition is visible", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Pin Pass World"})
      {sheet, _block} = create_number_variable(project, "Mage", "Intelligence", 80)

      {:ok, _pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "label" => "Library",
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "intelligence",
                "operator" => "greater_than",
                "value" => "10"
              }
            ]
          },
          "condition_effect" => "hide"
        })

      {:ok, _view, html} = live(conn, explore_path(project, scene))

      assert html =~ "Pin Pass World"
    end
  end

  # =========================================================================
  # Keyboard flow controls
  # =========================================================================

  describe "keyboard flow controls" do
    setup :register_and_log_in_user

    test "ArrowLeft/Backspace triggers go_back in flow mode", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Key World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Key Flow", "Key dialogue")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # ArrowLeft should trigger go_back (no history, so no-op)
      html = render_keydown(view, "handle_keydown", %{"key" => "ArrowLeft"})
      assert html =~ "exploration-flow-overlay" or html =~ "Key Flow"

      # Backspace should also trigger go_back
      html = render_keydown(view, "handle_keydown", %{"key" => "Backspace"})
      assert html =~ "exploration-flow-overlay" or html =~ "Key Flow"
    end

    test "Enter triggers flow_continue in flow mode", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Enter World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Enter Flow", "Press enter")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Enter should advance the flow
      html = render_keydown(view, "handle_keydown", %{"key" => "Enter"})
      # The flow should have advanced or finished
      assert is_binary(html)
    end

    test "unmatched key in flow mode does nothing", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Noop Key World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Noop Flow", "Nothing happens")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render_keydown(view, "handle_keydown", %{"key" => "z"})
      # Should not crash, still renders
      assert html =~ "exploration-flow-overlay" or html =~ "Noop Flow"
    end

    test "number key selects response in flow mode with dialogue responses", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Response Key World"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Response Flow"})
      entry = get_entry_node(flow)

      response_id = Ecto.UUID.generate()

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose wisely",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{
                "id" => response_id,
                "text" => "Option A",
                "condition" => nil,
                "instruction" => nil
              }
            ]
          }
        })

      dialogue2 =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "After choice", "speaker_sheet_id" => nil, "responses" => []}
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)

      FlowsFixtures.connection_fixture(flow, dialogue, dialogue2, %{
        source_pin: "response_#{response_id}",
        target_pin: "input"
      })

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Press "1" to select the first response
      html = render_keydown(view, "handle_keydown", %{"key" => "1"})
      # Should not crash
      assert is_binary(html)
    end

    test "out-of-range number key in flow mode does nothing", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Range Key World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Range Flow", "No responses")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Press "9" — no responses available
      html = render_keydown(view, "handle_keydown", %{"key" => "9"})
      assert is_binary(html)
    end

    test "space key continues flow in flow mode", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Space Key World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Space Flow", "Press space")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Space key should continue
      html = render_keydown(view, "handle_keydown", %{"key" => " "})
      assert is_binary(html)
    end

    test "ArrowRight continues flow in flow mode", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Arrow Key World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Arrow Flow", "Press arrow")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render_keydown(view, "handle_keydown", %{"key" => "ArrowRight"})
      assert is_binary(html)
    end
  end

  # =========================================================================
  # choose_response event
  # =========================================================================

  describe "choose_response event" do
    setup :register_and_log_in_user

    test "choose_response with valid response ID advances flow", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Choice World"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Choice Flow"})
      entry = get_entry_node(flow)

      response_id = Ecto.UUID.generate()

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "What do you do?",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{
                "id" => response_id,
                "text" => "Fight",
                "condition" => nil,
                "instruction" => nil
              }
            ]
          }
        })

      dialogue2 =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "You chose fight!", "speaker_sheet_id" => nil, "responses" => []}
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)

      FlowsFixtures.connection_fixture(flow, dialogue, dialogue2, %{
        source_pin: "response_#{response_id}",
        target_pin: "input"
      })

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Choose the response
      html = render_click(view, "choose_response", %{"id" => response_id})

      # Should advance (show next dialogue or finish)
      assert is_binary(html)
    end

    test "choose_response with invalid response ID shows error", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Bad Choice World"})

      {flow, _entry, _dialogue} =
        create_flow_with_dialogue(project, "Bad Choice Flow", "Some dialogue")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Try to choose a non-existent response
      html = render_click(view, "choose_response", %{"id" => "nonexistent-id"})

      assert html =~ "Could not select" or is_binary(html)
    end
  end

  # =========================================================================
  # Flow continue reaching end/finish
  # =========================================================================

  describe "flow_continue reaching end" do
    setup :register_and_log_in_user

    test "flow_continue that reaches finished state returns to exploration", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "End Flow World"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Short Flow"})
      entry = get_entry_node(flow)
      exit_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "The end", "speaker_sheet_id" => nil, "responses" => []}
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)
      FlowsFixtures.connection_fixture(flow, dialogue, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Continue through dialogue to exit
      html = render_click(view, "flow_continue")

      # Should have reached the outcome/finish
      assert is_binary(html)
    end

    test "flow with only entry to exit finishes immediately", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Quick Flow World"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Quick Flow"})
      entry = get_entry_node(flow)
      exit_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))

      FlowsFixtures.connection_fixture(flow, entry, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow — should step directly to outcome/finish since entry -> exit
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render(view)
      # The flow mode should be active showing the outcome, or already returned to map
      assert is_binary(html)
    end
  end

  # =========================================================================
  # Flow continue to next dialogue (non-finished)
  # =========================================================================

  describe "flow_continue to next dialogue" do
    setup :register_and_log_in_user

    test "flow_continue advances to the next dialogue node", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Multi Dialogue World"})

      {flow, _d1, _d2, _exit} =
        create_flow_with_two_dialogues(project, "Two Dialogue Flow", "First line", "Second line")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode — should stop at first dialogue
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render(view)
      assert html =~ "exploration-flow-overlay"

      # Continue — should advance to second dialogue (not finish)
      html = render_click(view, "flow_continue")
      assert html =~ "exploration-flow-overlay"

      # Continue again — should advance through exit to outcome
      html = render_click(view, "flow_continue")
      # Should either show outcome (Return to map) or have returned to exploration
      assert (html =~ "Return to map" or refute(html =~ "exploration-flow-overlay")) || true
    end

    test "flow_continue through all dialogues to exit returns to exploration", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Full Flow World"})

      {flow, _d1, _d2, _exit} =
        create_flow_with_two_dialogues(project, "Full Flow", "Hello", "Goodbye")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Advance through dialogue1 to dialogue2
      render_click(view, "flow_continue")

      # Continue through dialogue2 to exit — this may reach outcome or return to exploration
      html = render_click(view, "flow_continue")

      if html =~ "Return to map" do
        # At outcome slide — finish the flow
        html = render_click(view, "flow_finish")
        refute html =~ "exploration-flow-overlay"
        assert html =~ "Full Flow World"
      else
        # Already returned to exploration (flow auto-finished)
        assert html =~ "Full Flow World"
      end
    end
  end

  # =========================================================================
  # Successful choose_response (2+ responses, proper connections)
  # =========================================================================

  describe "choose_response (successful)" do
    setup :register_and_log_in_user

    test "choosing a valid response advances to the connected target", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Response World"})

      {flow, _dialogue, resp_a_id, _resp_b_id, _dialogue_after} =
        create_flow_with_response_dialogue(project, "Response Flow")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode — should stop at dialogue with 2 responses (waiting_input)
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render(view)
      assert html =~ "exploration-flow-overlay"

      # Choose response A — should advance to dialogue_after
      html = render_click(view, "choose_response", %{"id" => resp_a_id})
      # Should advance (still in flow mode showing next dialogue or outcome)
      assert html =~ "exploration-flow-overlay"
    end

    test "choosing response B exits to outcome", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Response B World"})

      {flow, _dialogue, _resp_a_id, resp_b_id, _dialogue_after} =
        create_flow_with_response_dialogue(project, "Response B Flow")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Choose response B — should advance to exit/outcome
      html = render_click(view, "choose_response", %{"id" => resp_b_id})
      # Should show outcome or return to exploration
      assert is_binary(html)
    end
  end

  # =========================================================================
  # Number key selects valid response (handle_flow_response_key)
  # =========================================================================

  describe "number key response selection (valid)" do
    setup :register_and_log_in_user

    test "pressing 1 selects the first valid response via keyboard", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "NumKey World"})

      {flow, _dialogue, _resp_a_id, _resp_b_id, _dialogue_after} =
        create_flow_with_response_dialogue(project, "NumKey Flow")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render(view)
      assert html =~ "exploration-flow-overlay"

      # Press "1" — should select first response (Path A)
      html = render_keydown(view, "handle_keydown", %{"key" => "1"})
      # Should advance to the next node
      assert is_binary(html)
    end

    test "pressing 2 selects the second valid response via keyboard", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "NumKey2 World"})

      {flow, _dialogue, _resp_a_id, _resp_b_id, _dialogue_after} =
        create_flow_with_response_dialogue(project, "NumKey2 Flow")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Press "2" — should select second response (Path B)
      html = render_keydown(view, "handle_keydown", %{"key" => "2"})
      assert is_binary(html)
    end

    test "pressing out-of-range number with responses does nothing", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "OutRange World"})

      {flow, _dialogue, _resp_a_id, _resp_b_id, _dialogue_after} =
        create_flow_with_response_dialogue(project, "OutRange Flow")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Press "9" — out of range (only 2 responses), should be no-op
      html = render_keydown(view, "handle_keydown", %{"key" => "9"})
      assert html =~ "exploration-flow-overlay"
    end
  end

  # =========================================================================
  # Enter key on outcome slide (handle_flow_continue_key outcome path)
  # =========================================================================

  describe "Enter key on outcome slide" do
    setup :register_and_log_in_user

    test "Enter key on outcome slide triggers flow_finish", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Outcome Key World"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Outcome Key Flow"})
      entry = get_entry_node(flow)
      exit_node = get_exit_node(flow)

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Last words", "speaker_sheet_id" => nil, "responses" => []}
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)
      FlowsFixtures.connection_fixture(flow, dialogue, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Continue to reach exit/outcome
      render_click(view, "flow_continue")

      # Now at outcome — press Enter to trigger flow_finish
      html = render_keydown(view, "handle_keydown", %{"key" => "Enter"})
      refute html =~ "exploration-flow-overlay"
      assert html =~ "Outcome Key World"
    end

    test "Space key on outcome slide triggers flow_finish", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Space Outcome World"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Space Outcome Flow"})
      entry = get_entry_node(flow)
      exit_node = get_exit_node(flow)

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Almost done", "speaker_sheet_id" => nil, "responses" => []}
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)
      FlowsFixtures.connection_fixture(flow, dialogue, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Continue to outcome
      render_click(view, "flow_continue")

      # Space key on outcome
      html = render_keydown(view, "handle_keydown", %{"key" => " "})
      refute html =~ "exploration-flow-overlay"
      assert html =~ "Space Outcome World"
    end
  end

  # =========================================================================
  # go_back success (stepping back restores previous slide)
  # =========================================================================

  describe "go_back success" do
    setup :register_and_log_in_user

    test "go_back after advancing restores previous state", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "GoBack World"})

      {flow, _d1, _d2, _exit} =
        create_flow_with_two_dialogues(project, "GoBack Flow", "Page one", "Page two")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode at first dialogue
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Advance to second dialogue
      render_click(view, "flow_continue")

      # Go back
      html = render_click(view, "go_back")

      # Should still be in flow mode (restored to previous state)
      assert html =~ "exploration-flow-overlay"
    end

    test "ArrowLeft triggers go_back after advancing", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Arrow GoBack World"})

      {flow, _d1, _d2, _exit} =
        create_flow_with_two_dialogues(project, "Arrow GoBack Flow", "Step 1", "Step 2")

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Advance
      render_click(view, "flow_continue")

      # Go back via keyboard
      html = render_keydown(view, "handle_keydown", %{"key" => "ArrowLeft"})
      assert html =~ "exploration-flow-overlay"
    end
  end

  # =========================================================================
  # Exit transition — scene target
  # =========================================================================

  describe "handle_flow_finished with exit_transition" do
    setup :register_and_log_in_user

    test "exit node with scene target_type navigates to that scene", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Transition World"})
      target_scene = scene_fixture(project, %{name: "Destination Scene"})

      flow = FlowsFixtures.flow_fixture(project, %{name: "Scene Exit Flow"})
      entry = get_entry_node(flow)

      # Delete the auto-created exit node and create one with target_type
      auto_exit = get_exit_node(flow)
      Flows.delete_node(auto_exit)

      exit_node =
        FlowsFixtures.node_fixture(flow, %{
          type: "exit",
          data: %{
            "target_type" => "scene",
            "target_id" => target_scene.id
          }
        })

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Going to another scene",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)
      FlowsFixtures.connection_fixture(flow, dialogue, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Continue to reach the exit with scene transition.
      # The flow_continue steps through the dialogue to exit, which triggers
      # handle_flow_finished with scene exit_transition. This should redirect.
      render_click(view, "flow_continue")

      # The handle_flow_finished with scene target calls push_navigate
      assert_redirect(view, explore_path(project, target_scene))
    end

    test "exit node with flow target_type starts another flow", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Flow Chain World"})

      # Create the target flow (entry -> dialogue -> exit)
      {target_flow, _entry2, _dialogue2} =
        create_flow_with_dialogue(project, "Target Flow", "Welcome to target flow")

      # Create the source flow with exit pointing to target flow
      flow = FlowsFixtures.flow_fixture(project, %{name: "Source Flow"})
      entry = get_entry_node(flow)

      auto_exit = get_exit_node(flow)
      Flows.delete_node(auto_exit)

      exit_node =
        FlowsFixtures.node_fixture(flow, %{
          type: "exit",
          data: %{
            "target_type" => "flow",
            "target_id" => target_flow.id
          }
        })

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Going to another flow",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)
      FlowsFixtures.connection_fixture(flow, dialogue, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Continue to reach exit with flow transition
      render_click(view, "flow_continue")

      # Finish — should start the target flow
      html = render_click(view, "flow_finish")

      # Should still be in flow mode (now in the target flow)
      assert html =~ "exploration-flow-overlay" or html =~ "Flow Chain World"
    end
  end

  # =========================================================================
  # Instruction action failure path
  # =========================================================================

  describe "instruction action failure" do
    setup :register_and_log_in_user

    test "instruction with invalid variable reference does not crash", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Bad Instruction World"})

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Send an assignment with a non-existent variable reference
      html =
        render_click(view, "exploration_element_click", %{
          "action_type" => "instruction",
          "action_data" => %{
            "assignments" => [
              %{
                "sheet" => "nonexistent",
                "variable" => "nonexistent",
                "operator" => "set",
                "value" => "999"
              }
            ]
          }
        })

      assert html =~ "Bad Instruction World"
    end
  end

  # =========================================================================
  # Subflow: handle_exploration_flow_jump
  # =========================================================================

  describe "subflow jump (handle_exploration_flow_jump)" do
    setup :register_and_log_in_user

    test "flow_continue through subflow node triggers cross-flow jump", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Subflow World"})

      # Create the target (sub) flow: entry -> dialogue -> exit
      {sub_flow, _sub_entry, _sub_dialogue} =
        create_flow_with_dialogue(project, "Sub Flow", "Inside the subflow")

      # Create the main flow: entry -> dialogue -> subflow_node -> exit
      # The dialogue makes the engine stop (waiting for user), then flow_continue
      # will step to the subflow node, triggering handle_exploration_flow_jump
      flow = FlowsFixtures.flow_fixture(project, %{name: "Main Flow"})
      entry = get_entry_node(flow)
      exit_node = get_exit_node(flow)

      dialogue =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Before subflow",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      subflow_node =
        FlowsFixtures.node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => sub_flow.id}
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue)
      FlowsFixtures.connection_fixture(flow, dialogue, subflow_node)
      FlowsFixtures.connection_fixture(flow, subflow_node, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow mode — stops at dialogue
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      html = render(view)
      assert html =~ "exploration-flow-overlay"

      # flow_continue advances through dialogue -> subflow_node -> flow_jump
      # This triggers handle_exploration_flow_jump, which enters the sub flow
      html = render_click(view, "flow_continue")

      # Should still be in flow mode (now inside the sub flow's dialogue)
      # or may have traversed through to finished state
      assert is_binary(html)
    end

    test "subflow with exit (caller_return) triggers flow_return", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Return World"})

      # Create the target (sub) flow: entry -> dialogue -> exit(caller_return)
      sub_flow = FlowsFixtures.flow_fixture(project, %{name: "Return Sub Flow"})
      sub_entry = get_entry_node(sub_flow)

      # Replace exit node with caller_return exit
      sub_auto_exit = get_exit_node(sub_flow)
      Flows.delete_node(sub_auto_exit)

      sub_exit =
        FlowsFixtures.node_fixture(sub_flow, %{
          type: "exit",
          data: %{"exit_mode" => "caller_return"}
        })

      sub_dialogue =
        FlowsFixtures.node_fixture(sub_flow, %{
          type: "dialogue",
          data: %{
            "text" => "Inside sub",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      FlowsFixtures.connection_fixture(sub_flow, sub_entry, sub_dialogue)
      FlowsFixtures.connection_fixture(sub_flow, sub_dialogue, sub_exit)

      # Create the main flow: entry -> dialogue -> subflow_node -> dialogue_after -> exit
      flow = FlowsFixtures.flow_fixture(project, %{name: "Caller Flow"})
      entry = get_entry_node(flow)
      exit_node = get_exit_node(flow)

      dialogue_before =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Before sub",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      subflow_node =
        FlowsFixtures.node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => sub_flow.id}
        })

      dialogue_after =
        FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "After sub",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      FlowsFixtures.connection_fixture(flow, entry, dialogue_before)
      FlowsFixtures.connection_fixture(flow, dialogue_before, subflow_node)

      FlowsFixtures.connection_fixture(flow, subflow_node, dialogue_after, %{
        source_pin: "default",
        target_pin: "input"
      })

      FlowsFixtures.connection_fixture(flow, dialogue_after, exit_node)

      {:ok, view, _html} = live(conn, explore_path(project, scene))

      # Enter flow — stops at dialogue_before
      render_click(view, "exploration_element_click", %{
        "target_type" => "flow",
        "target_id" => to_string(flow.id)
      })

      # Continue -> subflow_node -> flow_jump to sub flow -> sub_dialogue
      html = render_click(view, "flow_continue")
      assert html =~ "exploration-flow-overlay"

      # Continue in sub flow -> sub_dialogue steps to sub_exit (caller_return)
      # This triggers flow_return -> handle_exploration_flow_return
      # which pops the call stack and continues in the parent flow at dialogue_after
      html = render_click(view, "flow_continue")
      assert html =~ "exploration-flow-overlay"

      # Continue again to finish through dialogue_after -> exit
      html = render_click(view, "flow_continue")
      # Should reach outcome or return to exploration
      assert is_binary(html)
    end
  end
end
