defmodule StoryarnWeb.FlowLive.Nodes.Exit.NodeTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Nodes.Exit.Node, as: ExitNode

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Metadata functions
  # =============================================================================

  describe "type/0" do
    test "returns exit" do
      assert ExitNode.type() == "exit"
    end
  end

  describe "icon_name/0" do
    test "returns square" do
      assert ExitNode.icon_name() == "square"
    end
  end

  describe "label/0" do
    test "returns Exit" do
      assert ExitNode.label() == "Exit"
    end
  end

  # =============================================================================
  # default_data/0
  # =============================================================================

  describe "default_data/0" do
    test "returns map with expected keys and defaults" do
      data = ExitNode.default_data()

      assert data["label"] == ""
      assert data["technical_id"] == ""
      assert data["outcome_tags"] == []
      assert data["outcome_color"] == "#22c55e"
      assert data["exit_mode"] == "terminal"
      assert data["referenced_flow_id"] == nil
      assert data["target_type"] == nil
      assert data["target_id"] == nil
    end
  end

  # =============================================================================
  # extract_form_data/1
  # =============================================================================

  describe "extract_form_data/1" do
    test "extracts all exit fields from data" do
      data = %{
        "label" => "Success",
        "technical_id" => "flow_exit_1",
        "outcome_tags" => ["success", "win"],
        "outcome_color" => "#FF0000",
        "exit_mode" => "flow_reference",
        "referenced_flow_id" => 42,
        "target_type" => "scene",
        "target_id" => 99,
        "extra" => "ignored"
      }

      result = ExitNode.extract_form_data(data)

      assert result["label"] == "Success"
      assert result["technical_id"] == "flow_exit_1"
      assert result["outcome_tags"] == ["success", "win"]
      assert result["outcome_color"] == "#FF0000"
      assert result["exit_mode"] == "flow_reference"
      assert result["referenced_flow_id"] == 42
      assert result["target_type"] == "scene"
      assert result["target_id"] == 99
      refute Map.has_key?(result, "extra")
    end

    test "provides defaults for missing fields" do
      result = ExitNode.extract_form_data(%{})

      assert result["label"] == ""
      assert result["technical_id"] == ""
      assert result["outcome_tags"] == []
      assert result["outcome_color"] == "#22c55e"
      assert result["exit_mode"] == "terminal"
      assert result["referenced_flow_id"] == nil
      assert result["target_type"] == nil
      assert result["target_id"] == nil
    end

    test "parses comma-separated outcome_tags string" do
      data = %{"outcome_tags" => "success, Win, epic_victory"}
      result = ExitNode.extract_form_data(data)

      assert result["outcome_tags"] == ["success", "win", "epic_victory"]
    end

    test "deduplicates outcome_tags" do
      data = %{"outcome_tags" => "win, Win, WIN"}
      result = ExitNode.extract_form_data(data)

      assert result["outcome_tags"] == ["win"]
    end

    test "validates exit_mode falls back to terminal for invalid" do
      data = %{"exit_mode" => "invalid_mode"}
      result = ExitNode.extract_form_data(data)
      assert result["exit_mode"] == "terminal"
    end

    test "accepts all valid exit modes" do
      for mode <- ~w(terminal flow_reference caller_return) do
        result = ExitNode.extract_form_data(%{"exit_mode" => mode})
        assert result["exit_mode"] == mode
      end
    end

    test "parses string referenced_flow_id to integer" do
      result = ExitNode.extract_form_data(%{"referenced_flow_id" => "42"})
      assert result["referenced_flow_id"] == 42
    end

    test "returns nil for empty string referenced_flow_id" do
      result = ExitNode.extract_form_data(%{"referenced_flow_id" => ""})
      assert result["referenced_flow_id"] == nil
    end

    test "returns nil for invalid referenced_flow_id" do
      result = ExitNode.extract_form_data(%{"referenced_flow_id" => "abc"})
      assert result["referenced_flow_id"] == nil
    end

    test "validates target_type" do
      assert ExitNode.extract_form_data(%{"target_type" => "scene"})["target_type"] == "scene"
      assert ExitNode.extract_form_data(%{"target_type" => "flow"})["target_type"] == "flow"
      assert ExitNode.extract_form_data(%{"target_type" => "invalid"})["target_type"] == nil
    end

    test "parses string target_id to integer" do
      result = ExitNode.extract_form_data(%{"target_id" => "55"})
      assert result["target_id"] == 55
    end

    test "validates hex color format" do
      assert ExitNode.extract_form_data(%{"outcome_color" => "#abc"})["outcome_color"] == "#abc"

      assert ExitNode.extract_form_data(%{"outcome_color" => "#aabbcc"})["outcome_color"] ==
               "#aabbcc"

      assert ExitNode.extract_form_data(%{"outcome_color" => "not-a-color"})["outcome_color"] ==
               "#22c55e"
    end
  end

  # =============================================================================
  # on_double_click/1
  # =============================================================================

  describe "on_double_click/1" do
    test "returns :toolbar" do
      assert ExitNode.on_double_click(%{}) == :toolbar
    end
  end

  # =============================================================================
  # duplicate_data_cleanup/1
  # =============================================================================

  describe "duplicate_data_cleanup/1" do
    test "clears technical_id" do
      data = %{"technical_id" => "flow_exit_1", "label" => "Keep", "outcome_color" => "#FF0000"}
      result = ExitNode.duplicate_data_cleanup(data)

      assert result["technical_id"] == ""
      assert result["label"] == "Keep"
      assert result["outcome_color"] == "#FF0000"
    end
  end

  # =============================================================================
  # on_select/2
  # =============================================================================

  describe "on_select/2" do
    setup do
      project = project_fixture(user_fixture())
      flow = Storyarn.FlowsFixtures.flow_fixture(project)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flow: flow,
          project: project
        }
      }

      %{flow: flow, socket: socket, project: project}
    end

    test "assigns outcome_tags_suggestions and referencing_flows", %{socket: socket} do
      node = %{data: %{"exit_mode" => "caller_return"}}
      result = ExitNode.on_select(node, socket)

      assert Map.has_key?(result.assigns, :outcome_tags_suggestions)
      assert Map.has_key?(result.assigns, :referencing_flows)
      # Fresh project has no tags or referencing flows
      assert result.assigns.outcome_tags_suggestions == []
      assert result.assigns.referencing_flows == []
    end

    test "with terminal mode assigns available_scenes and available_flows", %{socket: socket} do
      node = %{data: %{"exit_mode" => "terminal"}}
      result = ExitNode.on_select(node, socket)

      assert Map.has_key?(result.assigns, :available_scenes)
      assert Map.has_key?(result.assigns, :available_flows)
    end

    test "with flow_reference mode assigns available_flows excluding current", %{
      socket: socket,
      flow: flow
    } do
      node = %{data: %{"exit_mode" => "flow_reference"}}
      result = ExitNode.on_select(node, socket)

      flow_ids = Enum.map(result.assigns.available_flows, & &1.id)
      refute flow.id in flow_ids
    end
  end

  # =============================================================================
  # Handler functions (require full socket with DB fixtures)
  # =============================================================================

  describe "handle_update_exit_mode/2" do
    setup :setup_exit_node_socket

    test "updates exit mode to flow_reference", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_update_exit_mode("flow_reference", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["exit_mode"] == "flow_reference"
      assert is_list(result.assigns.available_flows)
    end

    test "updates exit mode to caller_return", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_update_exit_mode("caller_return", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["exit_mode"] == "caller_return"
    end

    test "clears referenced_flow_id when switching to terminal", %{socket: socket, node: node} do
      # First set a flow reference
      Storyarn.Flows.update_node_data(node, Map.put(node.data, "referenced_flow_id", 999))

      {:noreply, result} = ExitNode.handle_update_exit_mode("terminal", socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert updated.data["referenced_flow_id"] == nil
      assert updated.data["exit_mode"] == "terminal"
    end

    test "falls back to terminal for invalid mode", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_update_exit_mode("invalid", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["exit_mode"] == "terminal"
    end
  end

  describe "handle_update_exit_reference/2" do
    setup :setup_exit_node_socket

    test "sets referenced flow ID", %{socket: socket, project: project} do
      other_flow = Storyarn.FlowsFixtures.flow_fixture(project)

      {:noreply, result} =
        ExitNode.handle_update_exit_reference(to_string(other_flow.id), socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["referenced_flow_id"] == other_flow.id
    end

    test "clears reference with nil", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_update_exit_reference(nil, socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["referenced_flow_id"] == nil
    end

    test "rejects self-reference", %{socket: socket, flow: flow} do
      {:noreply, result} = ExitNode.handle_update_exit_reference(to_string(flow.id), socket)

      assert result.assigns.flash["error"] =~ "Cannot reference the current flow"
    end
  end

  describe "handle_add_outcome_tag/2" do
    setup :setup_exit_node_socket

    test "adds normalized tag", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_add_outcome_tag("  Victory  ", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert "victory" in node.data["outcome_tags"]
    end

    test "normalizes spaces to underscores", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_add_outcome_tag("epic win", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert "epic_win" in node.data["outcome_tags"]
    end

    test "ignores empty tag", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_add_outcome_tag("  ", socket)
      assert result == socket
    end
  end

  describe "handle_remove_outcome_tag/2" do
    setup :setup_exit_node_socket

    test "removes specified tag", %{socket: socket, node: node} do
      Storyarn.Flows.update_node_data(node, Map.put(node.data, "outcome_tags", ["win", "lose"]))

      {:noreply, result} = ExitNode.handle_remove_outcome_tag("win", socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      refute "win" in updated.data["outcome_tags"]
      assert "lose" in updated.data["outcome_tags"]
    end
  end

  describe "handle_update_outcome_color/2" do
    setup :setup_exit_node_socket

    test "sets valid hex color", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_update_outcome_color("#FF0000", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["outcome_color"] == "#FF0000"
    end

    test "falls back to default for invalid color", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_update_outcome_color("not-a-color", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["outcome_color"] == "#22c55e"
    end
  end

  describe "handle_update_exit_target/2" do
    setup :setup_exit_node_socket

    test "sets valid scene target", %{socket: socket} do
      {:noreply, result} =
        ExitNode.handle_update_exit_target(
          %{"target_type" => "scene", "target_id" => "42"},
          socket
        )

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["target_type"] == "scene"
      assert node.data["target_id"] == 42
    end

    test "clears both when type is invalid", %{socket: socket} do
      {:noreply, result} =
        ExitNode.handle_update_exit_target(
          %{"target_type" => "invalid", "target_id" => "42"},
          socket
        )

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["target_type"] == nil
      assert node.data["target_id"] == nil
    end
  end

  describe "handle_generate_technical_id/1" do
    setup :setup_exit_node_socket

    test "generates technical ID from flow shortcut and label", %{socket: socket, node: node} do
      {:ok, updated_node, _} =
        Storyarn.Flows.update_node_data(node, Map.put(node.data, "label", "Victory"))

      socket = %{socket | assigns: %{socket.assigns | selected_node: updated_node}}

      {:noreply, result} = ExitNode.handle_generate_technical_id(socket)

      final = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert final.data["technical_id"] =~ "victory"
      assert final.data["technical_id"] =~ "_"
    end

    test "uses default parts when label is empty", %{socket: socket} do
      {:noreply, result} = ExitNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert updated.data["technical_id"] =~ "exit"
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_exit_node_socket(_context) do
    project = project_fixture(user_fixture())
    flow = Storyarn.FlowsFixtures.flow_fixture(project)

    node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "exit",
        data: ExitNode.default_data()
      })

    flow = Storyarn.Flows.get_flow!(project.id, flow.id)
    flow_data = Storyarn.Flows.serialize_for_canvas(flow)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        flow: flow,
        project: project,
        selected_node: node,
        flow_data: flow_data,
        flow_hubs: [],
        save_status: :idle
      },
      private: %{lifecycle_events: [], live_temp: %{}}
    }

    %{flow: flow, socket: socket, project: project, node: node}
  end
end
