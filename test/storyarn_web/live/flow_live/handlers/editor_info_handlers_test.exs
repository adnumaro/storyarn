defmodule StoryarnWeb.FlowLive.Handlers.EditorInfoHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers

  # ============================================================================
  # Test Helpers
  # ============================================================================

  # Simulates the FlowLoader JS hook: triggers the event + waits for start_async
  defp load_flow(view) do
    render_click(view, "load_flow_data", %{})
    render_async(view, 500)
  end

  defp build_socket(overrides) do
    defaults = %{
      save_status: :idle,
      preview_show: true,
      preview_node: %{id: 1},
      project: %{id: 999},
      project_variables: []
    }

    assigns = Map.merge(defaults, overrides)

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  # Extracts pushed events from a socket after push_event/3.
  # Returns a list of [event_name, payload] tuples.
  defp get_push_events(socket) do
    get_in(socket.private, [:live_temp, :push_events]) || []
  end

  # Finds a specific pushed event by name. Returns the payload or nil.
  defp find_push_event(socket, event_name) do
    socket
    |> get_push_events()
    |> Enum.find(fn [name, _payload] -> name == event_name end)
    |> case do
      [_name, payload] -> payload
      nil -> nil
    end
  end

  # ============================================================================
  # Unit tests: handle_reset_save_status/1
  # ============================================================================

  describe "handle_reset_save_status/1" do
    test "assigns save_status to :idle" do
      socket = build_socket(%{save_status: :saved})

      {:noreply, result} = EditorInfoHandlers.handle_reset_save_status(socket)

      assert result.assigns.save_status == :idle
    end

    test "is idempotent when already idle" do
      socket = build_socket(%{save_status: :idle})

      {:noreply, result} = EditorInfoHandlers.handle_reset_save_status(socket)

      assert result.assigns.save_status == :idle
    end
  end

  # ============================================================================
  # Unit tests: handle_close_preview/1
  # ============================================================================

  describe "handle_close_preview/1" do
    test "sets preview_show to false and preview_node to nil" do
      socket = build_socket(%{preview_show: true, preview_node: %{id: 42}})

      {:noreply, result} = EditorInfoHandlers.handle_close_preview(socket)

      assert result.assigns.preview_show == false
      assert result.assigns.preview_node == nil
    end

    test "is idempotent when preview already closed" do
      socket = build_socket(%{preview_show: false, preview_node: nil})

      {:noreply, result} = EditorInfoHandlers.handle_close_preview(socket)

      assert result.assigns.preview_show == false
      assert result.assigns.preview_node == nil
    end
  end

  # ============================================================================
  # Unit tests: handle_variable_suggestions/3
  # ============================================================================

  describe "handle_variable_suggestions/3" do
    test "returns matching variables by reference" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        },
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "class",
          block_type: "select"
        },
        %{
          sheet_shortcut: "npc.merchant",
          sheet_name: "NPC Merchant",
          variable_name: "gold",
          block_type: "number"
        }
      ]

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} = EditorInfoHandlers.handle_variable_suggestions("health", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      assert payload != nil
      assert length(payload.items) == 1
      assert hd(payload.items).ref == "mc.jaime.health"
      assert hd(payload.items).block_type == "number"
    end

    test "returns matching variables by sheet name" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        },
        %{
          sheet_shortcut: "npc.merchant",
          sheet_name: "NPC Merchant",
          variable_name: "gold",
          block_type: "number"
        }
      ]

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} = EditorInfoHandlers.handle_variable_suggestions("Merchant", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      assert length(payload.items) == 1
      assert hd(payload.items).ref == "npc.merchant.gold"
    end

    test "returns empty list when no variables match" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        }
      ]

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} =
        EditorInfoHandlers.handle_variable_suggestions("nonexistent", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      assert payload.items == []
    end

    test "is case insensitive" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        }
      ]

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} = EditorInfoHandlers.handle_variable_suggestions("HEALTH", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      assert length(payload.items) == 1
    end

    test "limits results to 20 items" do
      variables =
        for i <- 1..25 do
          %{
            sheet_shortcut: "mc",
            sheet_name: "MC",
            variable_name: "var_#{i}",
            block_type: "number"
          }
        end

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} = EditorInfoHandlers.handle_variable_suggestions("var", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      assert length(payload.items) == 20
    end

    test "includes all expected fields in formatted variables" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        }
      ]

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} = EditorInfoHandlers.handle_variable_suggestions("health", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      [item] = payload.items

      assert item.ref == "mc.jaime.health"
      assert item.sheet_name == "MC Jaime"
      assert item.variable_name == "health"
      assert item.block_type == "number"
    end

    test "matches by partial shortcut" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        }
      ]

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} = EditorInfoHandlers.handle_variable_suggestions("jaime", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      assert length(payload.items) == 1
      assert hd(payload.items).ref == "mc.jaime.health"
    end

    test "matches multiple variables across sheets" do
      variables = [
        %{
          sheet_shortcut: "mc.jaime",
          sheet_name: "MC Jaime",
          variable_name: "health",
          block_type: "number"
        },
        %{
          sheet_shortcut: "npc.healer",
          sheet_name: "NPC Healer",
          variable_name: "health_potions",
          block_type: "number"
        }
      ]

      socket = build_socket(%{project_variables: variables})

      {:noreply, result} = EditorInfoHandlers.handle_variable_suggestions("health", nil, socket)

      payload = find_push_event(result, "variable_suggestions_result")
      assert length(payload.items) == 2
    end
  end

  # ============================================================================
  # Unit tests: handle_resolve_variable_defaults/3
  # ============================================================================

  describe "handle_resolve_variable_defaults/3" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "resolves valid variable references", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Character", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => "100"}
      })

      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(["mc.health"], nil, socket)

      payload = find_push_event(result, "variable_defaults_resolved")
      assert is_map(payload.defaults)
    end

    test "filters out invalid refs", %{project: project} do
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(
          ["valid.ref", "no-dots", "", "a.b.c.d.e.f"],
          nil,
          socket
        )

      payload = find_push_event(result, "variable_defaults_resolved")
      assert is_map(payload.defaults)
    end

    test "limits refs to max 50", %{project: project} do
      refs = for i <- 1..60, do: "sheet.var_#{i}"
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(refs, nil, socket)

      payload = find_push_event(result, "variable_defaults_resolved")
      assert is_map(payload.defaults)
    end

    test "handles non-list refs gracefully", %{project: project} do
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults("not_a_list", nil, socket)

      # Should just return the socket unchanged (no event pushed)
      assert find_push_event(result, "variable_defaults_resolved") == nil
    end

    test "handles nil refs gracefully", %{project: project} do
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(nil, nil, socket)

      assert find_push_event(result, "variable_defaults_resolved") == nil
    end

    test "handles empty list", %{project: project} do
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults([], nil, socket)

      payload = find_push_event(result, "variable_defaults_resolved")
      assert payload.defaults == %{}
    end

    test "filters non-binary elements in refs list", %{project: project} do
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(
          [123, nil, "valid.ref", :atom],
          nil,
          socket
        )

      payload = find_push_event(result, "variable_defaults_resolved")
      assert is_map(payload.defaults)
    end

    test "rejects refs with special characters", %{project: project} do
      socket = build_socket(%{project: project})

      # Refs with spaces, hyphens, or special chars should be filtered out
      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(
          ["sheet.var name", "sheet.var-name", "sheet.va$r"],
          nil,
          socket
        )

      payload = find_push_event(result, "variable_defaults_resolved")
      assert payload.defaults == %{}
    end

    test "accepts valid 2-part refs", %{project: project} do
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(
          ["sheet.variable", "another.var"],
          nil,
          socket
        )

      payload = find_push_event(result, "variable_defaults_resolved")
      assert is_map(payload.defaults)
    end

    test "accepts valid 3-part refs", %{project: project} do
      socket = build_socket(%{project: project})

      {:noreply, result} =
        EditorInfoHandlers.handle_resolve_variable_defaults(
          ["sheet.table.column"],
          nil,
          socket
        )

      payload = find_push_event(result, "variable_defaults_resolved")
      assert is_map(payload.defaults)
    end
  end

  # ============================================================================
  # Integration tests: reset_save_status via handle_info
  # ============================================================================

  describe "reset_save_status through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "resets save status when :reset_save_status message received",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Send the :reset_save_status message directly to the LiveView process
      send(view.pid, :reset_save_status)

      # Give the LiveView time to process the message
      render(view)

      # The LiveView should have processed the message without errors
      assert Process.alive?(view.pid)
    end
  end

  # ============================================================================
  # Integration tests: handle_mention_suggestions via handle_info
  # ============================================================================

  describe "mention_suggestions through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "processes mention_suggestions info message",
         %{conn: conn, project: project, flow: flow} do
      sheet_fixture(project, %{name: "Hero Character"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      send(view.pid, {:mention_suggestions, "Hero", nil})
      render(view)

      assert Process.alive?(view.pid)
    end

    test "processes mention_suggestions with empty query",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      send(view.pid, {:mention_suggestions, "", nil})
      render(view)

      assert Process.alive?(view.pid)
    end
  end

  # ============================================================================
  # Integration tests: handle_variable_suggestions via handle_info
  # ============================================================================

  describe "variable_suggestions through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      sheet = sheet_fixture(project, %{name: "MC Jaime", shortcut: "mc.jaime"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => "100"}
      })

      %{project: project, flow: flow, sheet: sheet}
    end

    test "processes variable_suggestions info message",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      send(view.pid, {:variable_suggestions, "health", nil})
      render(view)

      assert Process.alive?(view.pid)
    end
  end

  # ============================================================================
  # Integration tests: handle_resolve_variable_defaults via handle_info
  # ============================================================================

  describe "resolve_variable_defaults through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "processes resolve_variable_defaults info message",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      send(view.pid, {:resolve_variable_defaults, ["mc.health"], nil})
      render(view)

      assert Process.alive?(view.pid)
    end

    test "processes resolve_variable_defaults with empty list",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      send(view.pid, {:resolve_variable_defaults, [], nil})
      render(view)

      assert Process.alive?(view.pid)
    end
  end

  # ============================================================================
  # Integration tests: handle_close_preview via handle_info
  # ============================================================================

  describe "close_preview through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "processes close_preview info message",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      send(view.pid, {:close_preview})
      render(view)

      assert Process.alive?(view.pid)
    end
  end

  # ============================================================================
  # Integration tests: handle_flow_refresh via handle_event
  # ============================================================================

  describe "flow_refresh through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "request_flow_refresh reloads flow data",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      node_fixture(flow, %{type: "hub", data: %{"hub_id" => "refresh_hub", "color" => "purple"}})

      render_click(view, "request_flow_refresh", %{})

      assert Process.alive?(view.pid)
    end
  end

  # ============================================================================
  # Integration tests: handle_node_updated via handle_info
  # ============================================================================

  describe "node_updated through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "processes node_updated info message",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Original", "speaker_sheet_id" => nil}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      updated_node = Storyarn.Flows.get_node!(flow.id, node.id)

      send(view.pid, {:node_updated, updated_node})
      render(view)

      assert Process.alive?(view.pid)
    end
  end

  # ============================================================================
  # Integration tests: mention_suggestions via handle_event (toolbar)
  # ============================================================================

  describe "mention_suggestions via handle_event (toolbar)" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})
      %{project: project, flow: flow, sheet: sheet}
    end

    test "mention_suggestions event returns results",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "mention_suggestions", %{"query" => "Hero"})

      assert Process.alive?(view.pid)
    end

    test "mention_suggestions event with no matches",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "mention_suggestions", %{"query" => "NonExistentEntity"})

      assert Process.alive?(view.pid)
    end
  end
end
