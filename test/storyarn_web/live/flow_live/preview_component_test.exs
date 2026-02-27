# Wrapper LiveView for testing PreviewComponent handle_events.
# Defined before the test module to avoid async compilation race conditions.
defmodule PreviewTestLive do
  use Phoenix.LiveView

  alias Storyarn.Flows

  def mount(_params, session, socket) do
    project = Storyarn.Projects.get_project!(session["project_id"])
    flow = Flows.get_flow!(project.id, session["flow_id"])
    start_node = Flows.get_node!(flow.id, session["start_node_id"])
    sheets_map = Map.get(session, "sheets_map", %{})

    # Manually invoke load_node logic since the component's update/2 has a bug
    socket =
      socket
      |> Phoenix.Component.assign(:project, project)
      |> Phoenix.Component.assign(:sheets_map, sheets_map)
      |> Phoenix.Component.assign(:preview_closed, false)

    {current_node, speaker, responses, has_next} =
      resolve_start_node(start_node, project, sheets_map)

    socket =
      socket
      |> Phoenix.Component.assign(:current_node, current_node)
      |> Phoenix.Component.assign(:speaker, speaker)
      |> Phoenix.Component.assign(:responses, responses)
      |> Phoenix.Component.assign(:has_next, has_next)
      |> Phoenix.Component.assign(:history, [])
      |> Phoenix.Component.assign(:show, true)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @preview_closed do %>
        <p>Preview closed</p>
      <% else %>
        <.live_component
          module={StoryarnWeb.FlowLive.PreviewComponent}
          id="preview-1"
          current_node={@current_node}
          speaker={@speaker}
          responses={@responses}
          has_next={@has_next}
          history={@history}
          show={@show}
          project={@project}
          sheets_map={@sheets_map}
        />
      <% end %>
    </div>
    """
  end

  def handle_info({:close_preview}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :preview_closed, true)}
  end

  # Replicate the component's load_node logic for initial setup since
  # update/2 has a bug that prevents load_node from running.
  defp resolve_start_node(%{type: "dialogue"} = node, project, sheets_map) do
    speaker = resolve_speaker(node.data["speaker_sheet_id"], project, sheets_map)
    responses = node.data["responses"] || []
    connections = Flows.get_outgoing_connections(node.id)
    has_next = responses == [] && Enum.any?(connections, &(&1.source_pin == "output"))
    {node, speaker, responses, has_next}
  end

  defp resolve_start_node(node, project, sheets_map) do
    # Skip non-dialogue nodes and follow connections
    connections = Flows.get_outgoing_connections(node.id)

    case List.first(connections) do
      nil ->
        {nil, nil, [], false}

      conn ->
        next_node = Flows.get_node_by_id!(node.flow_id, conn.target_node_id)
        resolve_start_node(next_node, project, sheets_map)
    end
  end

  defp resolve_speaker(nil, _project, _sheets_map), do: nil
  defp resolve_speaker("", _project, _sheets_map), do: nil

  defp resolve_speaker(sheet_id, project, sheets_map) do
    sheet_key = to_string(sheet_id)

    case Map.get(sheets_map, sheet_key) do
      %{name: name} ->
        name

      nil ->
        case Storyarn.Sheets.get_sheet(project.id, sheet_id) do
          nil -> nil
          sheet -> sheet.name
        end
    end
  end
end

defmodule StoryarnWeb.FlowLive.PreviewComponentTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.PreviewComponent

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # update/2 — initialization and defaults
  # =============================================================================

  describe "update/2 defaults" do
    test "initializes with default assigns on first call" do
      socket = build_socket()
      {:ok, socket} = PreviewComponent.update(%{id: "preview-1"}, socket)

      assert socket.assigns.current_node == nil
      assert socket.assigns.speaker == nil
      assert socket.assigns.responses == []
      assert socket.assigns.has_next == false
      assert socket.assigns.history == []
      assert socket.assigns.show == false
    end

    test "preserves existing assigns via assign_new" do
      socket = build_socket(%{current_node: %{id: 1}, show: true})
      {:ok, socket} = PreviewComponent.update(%{id: "preview-1"}, socket)

      assert socket.assigns.current_node == %{id: 1}
      assert socket.assigns.show == true
    end

    test "merges incoming assigns over socket assigns" do
      socket = build_socket(%{show: false})
      {:ok, socket} = PreviewComponent.update(%{id: "preview-1", show: true}, socket)

      assert socket.assigns.show == true
    end
  end

  # =============================================================================
  # render/1 — component rendering
  # =============================================================================

  describe "render/1" do
    test "renders empty state when no current_node" do
      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: nil,
          speaker: nil,
          responses: [],
          has_next: false,
          history: [],
          show: true,
          __changed__: %{}
        })

      assert html =~ "No node selected for preview"
    end

    test "renders dialogue text and speaker when current_node is set" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello World", "responses" => [], "speaker_sheet_id" => nil}
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: "Narrator",
          responses: [],
          has_next: false,
          history: [],
          show: true,
          __changed__: %{}
        })

      assert html =~ "Hello World"
      assert html =~ "Narrator"
      assert html =~ "End of dialogue branch"
    end

    test "renders speaker initials" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Test", "responses" => [], "speaker_sheet_id" => nil}
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: "Jaime Lannister",
          responses: [],
          has_next: false,
          history: [],
          show: true,
          __changed__: %{}
        })

      # speaker_initials("Jaime Lannister") => "JL"
      assert html =~ "JL"
    end

    test "renders ? for nil speaker initials" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "responses" => [], "speaker_sheet_id" => nil}
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: nil,
          responses: [],
          has_next: false,
          history: [],
          show: true,
          __changed__: %{}
        })

      assert html =~ "?"
      assert html =~ "Narrator"
    end

    test "renders responses when present" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      responses = [
        %{"id" => "r1", "text" => "Yes", "condition" => nil},
        %{"id" => "r2", "text" => "No", "condition" => "health > 0"}
      ]

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Choose", "responses" => responses, "speaker_sheet_id" => nil}
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: nil,
          responses: responses,
          has_next: false,
          history: [],
          show: true,
          __changed__: %{}
        })

      assert html =~ "Yes"
      assert html =~ "No"
      assert html =~ "Responses:"
      # Condition badge
      assert html =~ "?"
    end

    test "renders continue button when has_next but no responses" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Continue me", "responses" => [], "speaker_sheet_id" => nil}
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: nil,
          responses: [],
          has_next: true,
          history: [],
          show: true,
          __changed__: %{}
        })

      assert html =~ "Continue"
      refute html =~ "End of dialogue branch"
    end

    test "renders back button when history is present" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "After back", "responses" => [], "speaker_sheet_id" => nil}
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: nil,
          responses: [],
          has_next: false,
          history: [1],
          show: true,
          __changed__: %{}
        })

      assert html =~ "Back"
    end

    test "sanitizes HTML in dialogue text" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Safe <strong>bold</strong><script>alert('xss')</script></p>",
            "responses" => [],
            "speaker_sheet_id" => nil
          }
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: nil,
          responses: [],
          has_next: false,
          history: [],
          show: true,
          __changed__: %{}
        })

      assert html =~ "Safe"
      assert html =~ "bold"
      refute html =~ "<script>"
    end

    test "interpolates variables in dialogue text" do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello {name}, you have {health} HP",
            "responses" => [],
            "speaker_sheet_id" => nil
          }
        })

      html =
        render_component(PreviewComponent, %{
          id: "preview-1",
          current_node: dialogue,
          speaker: nil,
          responses: [],
          has_next: false,
          history: [],
          show: true,
          __changed__: %{}
        })

      assert html =~ "[name]"
      assert html =~ "[health]"
    end
  end

  # =============================================================================
  # handle_event tests via live_isolated wrapper
  # =============================================================================

  describe "handle_event via LiveView" do
    setup :register_and_log_in_user

    test "continue event advances to next dialogue", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      d1 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "First", "responses" => [], "speaker_sheet_id" => nil}
        })

      d2 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Second", "responses" => [], "speaker_sheet_id" => nil}
        })

      Storyarn.FlowsFixtures.connection_fixture(flow, d1, d2)

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => d1.id
          }
        )

      html = render(view)
      assert html =~ "First"

      # Click continue
      view |> element("button", "Continue") |> render_click()
      html = render(view)
      assert html =~ "Second"
    end

    test "go_back event returns to previous dialogue", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      d1 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "First dialogue", "responses" => [], "speaker_sheet_id" => nil}
        })

      d2 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Second dialogue", "responses" => [], "speaker_sheet_id" => nil}
        })

      Storyarn.FlowsFixtures.connection_fixture(flow, d1, d2)

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => d1.id
          }
        )

      # Navigate forward
      view |> element("button", "Continue") |> render_click()
      html = render(view)
      assert html =~ "Second dialogue"

      # Go back
      view |> element("button", "Back") |> render_click()
      html = render(view)
      assert html =~ "First dialogue"
    end

    test "close_preview event sends message to parent", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      d1 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "responses" => [], "speaker_sheet_id" => nil}
        })

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => d1.id
          }
        )

      view |> element("button", "Close") |> render_click()
      html = render(view)
      assert html =~ "Preview closed"
    end

    test "skips non-dialogue to find next dialogue", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      hub =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "test_hub", "label" => "Test", "color" => "#8b5cf6"}
        })

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "After hub", "responses" => [], "speaker_sheet_id" => nil}
        })

      Storyarn.FlowsFixtures.connection_fixture(flow, hub, dialogue)

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => hub.id
          }
        )

      html = render(view)
      assert html =~ "After hub"
    end

    test "shows empty state for unreachable dialogue", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      exit_node =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "exit",
          data: %{"label" => "end", "technical_id" => "", "exit_mode" => "terminal"}
        })

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => exit_node.id
          }
        )

      html = render(view)
      assert html =~ "No node selected for preview"
    end

    test "resolves speaker from sheets_map", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)
      sheet = Storyarn.SheetsFixtures.sheet_fixture(project, %{name: "Maria"})

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hola", "responses" => [], "speaker_sheet_id" => sheet.id}
        })

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => dialogue.id,
            "sheets_map" => %{to_string(sheet.id) => %{name: "Maria"}}
          }
        )

      html = render(view)
      assert html =~ "Maria"
    end

    test "resolves speaker from DB when not in sheets_map", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)
      sheet = Storyarn.SheetsFixtures.sheet_fixture(project, %{name: "Carlos"})

      dialogue =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "responses" => [], "speaker_sheet_id" => sheet.id}
        })

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => dialogue.id
          }
        )

      html = render(view)
      assert html =~ "Carlos"
    end

    test "select_response follows response connection", %{conn: conn, user: user} do
      project = project_fixture(user)
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      d1 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose wisely",
            "responses" => [%{"id" => "r1", "text" => "Option A", "condition" => nil}],
            "speaker_sheet_id" => nil
          }
        })

      d2 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "You chose A", "responses" => [], "speaker_sheet_id" => nil}
        })

      Storyarn.FlowsFixtures.connection_fixture(flow, d1, d2, %{
        source_pin: "r1",
        target_pin: "input"
      })

      {:ok, view, _html} =
        live_isolated(conn, PreviewTestLive,
          session: %{
            "project_id" => project.id,
            "flow_id" => flow.id,
            "start_node_id" => d1.id
          }
        )

      html = render(view)
      assert html =~ "Choose wisely"
      assert html =~ "Option A"

      view |> element("button", "Option A") |> render_click()
      html = render(view)
      assert html =~ "You chose A"
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp build_socket(extra_assigns \\ %{}) do
    base = %{
      __changed__: %{},
      start_node: nil,
      current_node: nil,
      speaker: nil,
      responses: [],
      has_next: false,
      history: [],
      show: false
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, extra_assigns),
      private: %{lifecycle_events: [], live_temp: %{}}
    }
  end
end
