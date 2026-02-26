defmodule StoryarnWeb.FlowLive.Nodes.Subflow.NodeTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Nodes.Subflow.Node, as: SubflowNode

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Metadata functions
  # =============================================================================

  describe "type/0" do
    test "returns subflow" do
      assert SubflowNode.type() == "subflow"
    end
  end

  describe "icon_name/0" do
    test "returns box" do
      assert SubflowNode.icon_name() == "box"
    end
  end

  describe "label/0" do
    test "returns Subflow" do
      assert SubflowNode.label() == "Subflow"
    end
  end

  # =============================================================================
  # default_data/0
  # =============================================================================

  describe "default_data/0" do
    test "returns map with referenced_flow_id nil" do
      data = SubflowNode.default_data()
      assert data == %{"referenced_flow_id" => nil}
    end
  end

  # =============================================================================
  # extract_form_data/1
  # =============================================================================

  describe "extract_form_data/1" do
    test "extracts referenced_flow_id" do
      data = %{"referenced_flow_id" => 42, "extra" => "ignored"}
      result = SubflowNode.extract_form_data(data)

      assert result == %{"referenced_flow_id" => 42}
      refute Map.has_key?(result, "extra")
    end

    test "handles nil referenced_flow_id" do
      result = SubflowNode.extract_form_data(%{"referenced_flow_id" => nil})
      assert result == %{"referenced_flow_id" => nil}
    end

    test "handles missing key" do
      result = SubflowNode.extract_form_data(%{})
      assert result == %{"referenced_flow_id" => nil}
    end
  end

  # =============================================================================
  # on_double_click/1
  # =============================================================================

  describe "on_double_click/1" do
    test "navigates to referenced flow" do
      node = %{data: %{"referenced_flow_id" => 42}}
      assert SubflowNode.on_double_click(node) == {:navigate, 42}
    end

    test "returns :toolbar when no reference" do
      assert SubflowNode.on_double_click(%{data: %{"referenced_flow_id" => nil}}) == :toolbar
    end

    test "returns :toolbar for empty string reference" do
      assert SubflowNode.on_double_click(%{data: %{"referenced_flow_id" => ""}}) == :toolbar
    end
  end

  # =============================================================================
  # duplicate_data_cleanup/1
  # =============================================================================

  describe "duplicate_data_cleanup/1" do
    test "preserves data unchanged" do
      data = %{"referenced_flow_id" => 42}
      assert SubflowNode.duplicate_data_cleanup(data) == data
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

    test "assigns available_flows and empty subflow_exits when no reference", %{socket: socket} do
      node = %{data: %{"referenced_flow_id" => nil}}
      result = SubflowNode.on_select(node, socket)

      assert Map.has_key?(result.assigns, :available_flows)
      assert result.assigns.subflow_exits == []
    end

    test "assigns available_flows excluding current flow", %{
      socket: socket,
      project: project,
      flow: flow
    } do
      _other_flow = Storyarn.FlowsFixtures.flow_fixture(project)
      node = %{data: %{"referenced_flow_id" => nil}}
      result = SubflowNode.on_select(node, socket)

      flow_ids = Enum.map(result.assigns.available_flows, & &1.id)
      refute flow.id in flow_ids
    end

    test "loads exit nodes when referenced flow exists", %{socket: socket, project: project} do
      other_flow = Storyarn.FlowsFixtures.flow_fixture(project)

      exit_node =
        Storyarn.FlowsFixtures.node_fixture(other_flow, %{
          type: "exit",
          data: %{"label" => "Done", "technical_id" => ""}
        })

      node = %{data: %{"referenced_flow_id" => other_flow.id}}
      result = SubflowNode.on_select(node, socket)

      exit_ids = Enum.map(result.assigns.subflow_exits, & &1.id)
      assert exit_node.id in exit_ids
    end

    test "returns empty exits for empty string reference", %{socket: socket} do
      node = %{data: %{"referenced_flow_id" => ""}}
      result = SubflowNode.on_select(node, socket)

      assert result.assigns.subflow_exits == []
    end
  end

  # =============================================================================
  # handle_update_reference/2
  # =============================================================================

  describe "handle_update_reference/2" do
    setup :setup_subflow_socket

    test "sets referenced flow ID", %{socket: socket, project: project} do
      other_flow = Storyarn.FlowsFixtures.flow_fixture(project)

      {:noreply, result} =
        SubflowNode.handle_update_reference(to_string(other_flow.id), socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["referenced_flow_id"] == to_string(other_flow.id)
    end

    test "clears reference with empty string", %{socket: socket} do
      {:noreply, result} = SubflowNode.handle_update_reference("", socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["referenced_flow_id"] == nil
    end

    test "rejects self-reference", %{socket: socket, flow: flow} do
      {:noreply, result} = SubflowNode.handle_update_reference(to_string(flow.id), socket)
      assert result.assigns.flash["error"] =~ "cannot reference itself"
    end

    test "does nothing when no node selected", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | selected_node: nil}}
      {:noreply, result} = SubflowNode.handle_update_reference("123", socket)
      assert result == socket
    end

    test "rejects invalid flow ID string", %{socket: socket} do
      {:noreply, result} = SubflowNode.handle_update_reference("not_a_number", socket)
      assert result.assigns.flash["error"] =~ "Invalid flow reference"
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_subflow_socket(_context) do
    project = project_fixture(user_fixture())
    flow = Storyarn.FlowsFixtures.flow_fixture(project)

    node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "subflow",
        data: SubflowNode.default_data()
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
