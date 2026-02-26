defmodule StoryarnWeb.FlowLive.Nodes.Condition.NodeTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Nodes.Condition.Node, as: ConditionNode

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Metadata functions
  # =============================================================================

  describe "type/0" do
    test "returns condition" do
      assert ConditionNode.type() == "condition"
    end
  end

  describe "icon_name/0" do
    test "returns git-branch" do
      assert ConditionNode.icon_name() == "git-branch"
    end
  end

  describe "label/0" do
    test "returns Condition" do
      assert ConditionNode.label() == "Condition"
    end
  end

  # =============================================================================
  # default_data/0
  # =============================================================================

  describe "default_data/0" do
    test "returns map with default condition and switch_mode" do
      data = ConditionNode.default_data()

      assert data["condition"] == %{"logic" => "all", "rules" => []}
      assert data["switch_mode"] == false
    end
  end

  # =============================================================================
  # extract_form_data/1
  # =============================================================================

  describe "extract_form_data/1" do
    test "extracts condition and switch_mode" do
      data = %{
        "condition" => %{"logic" => "any", "rules" => [%{"var" => "x"}]},
        "switch_mode" => true,
        "extra" => "ignored"
      }

      result = ConditionNode.extract_form_data(data)

      assert result["condition"] == %{"logic" => "any", "rules" => [%{"var" => "x"}]}
      assert result["switch_mode"] == true
      refute Map.has_key?(result, "extra")
    end

    test "provides defaults for missing fields" do
      result = ConditionNode.extract_form_data(%{})

      assert result["condition"] == %{"logic" => "all", "rules" => []}
      assert result["switch_mode"] == false
    end

    test "handles nil condition" do
      result = ConditionNode.extract_form_data(%{"condition" => nil})
      assert result["condition"] == %{"logic" => "all", "rules" => []}
    end

    test "handles nil switch_mode" do
      result = ConditionNode.extract_form_data(%{"switch_mode" => nil})
      assert result["switch_mode"] == false
    end
  end

  # =============================================================================
  # on_select/2, on_double_click/1, duplicate_data_cleanup/1
  # =============================================================================

  describe "on_select/2" do
    test "returns socket unchanged" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      assert ConditionNode.on_select(%{}, socket) == socket
    end
  end

  describe "on_double_click/1" do
    test "returns :builder" do
      assert ConditionNode.on_double_click(%{}) == :builder
    end
  end

  describe "duplicate_data_cleanup/1" do
    test "returns data unchanged" do
      data = %{"condition" => %{"logic" => "all", "rules" => []}, "switch_mode" => true}
      assert ConditionNode.duplicate_data_cleanup(data) == data
    end
  end

  # =============================================================================
  # handle_update_condition_builder/2
  # =============================================================================

  describe "handle_update_condition_builder/2" do
    setup :setup_condition_socket

    test "updates condition data on condition node", %{socket: socket} do
      condition_data = %{
        "logic" => "any",
        "rules" => [%{"variable" => "health", "operator" => "greater_than", "value" => "50"}]
      }

      {:noreply, result} =
        ConditionNode.handle_update_condition_builder(%{"condition" => condition_data}, socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["condition"]["logic"] == "any"
      assert length(node.data["condition"]["rules"]) == 1
      assert hd(node.data["condition"]["rules"])["variable"] == "health"
    end

    test "ignores update when no node selected", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | selected_node: nil}}

      {:noreply, result} =
        ConditionNode.handle_update_condition_builder(
          %{"condition" => %{"logic" => "all", "rules" => []}},
          socket
        )

      assert result == socket
    end

    test "ignores update when node is not condition type", %{socket: socket} do
      non_condition = %{socket.assigns.selected_node | type: "dialogue"}
      socket = %{socket | assigns: %{socket.assigns | selected_node: non_condition}}

      {:noreply, result} =
        ConditionNode.handle_update_condition_builder(
          %{"condition" => %{"logic" => "all", "rules" => []}},
          socket
        )

      assert result == socket
    end

    test "handles params without condition key", %{socket: socket} do
      {:noreply, result} = ConditionNode.handle_update_condition_builder(%{}, socket)
      assert result == socket
    end
  end

  # =============================================================================
  # handle_update_response_condition_builder/2
  # =============================================================================

  describe "handle_update_response_condition_builder/2" do
    setup :setup_condition_socket

    test "updates response condition on a dialogue node", %{socket: socket, flow: flow} do
      # Create a dialogue node with a response
      dialogue_node =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => "Yes", "condition" => nil}
            ]
          }
        })

      condition_data = %{"logic" => "all", "rules" => [%{"variable" => "hp"}]}

      {:noreply, result} =
        ConditionNode.handle_update_response_condition_builder(
          %{
            "condition" => condition_data,
            "response-id" => "r1",
            "node-id" => dialogue_node.id
          },
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, dialogue_node.id)
      response = Enum.find(updated.data["responses"], &(&1["id"] == "r1"))
      # Condition is stored as JSON string on responses
      condition =
        if is_binary(response["condition"]),
          do: Jason.decode!(response["condition"]),
          else: response["condition"]

      assert condition["logic"] == "all"
      assert length(condition["rules"]) == 1
      assert hd(condition["rules"])["variable"] == "hp"
    end

    test "handles missing node-id", %{socket: socket} do
      {:noreply, result} =
        ConditionNode.handle_update_response_condition_builder(
          %{"condition" => %{}, "response-id" => "r1", "node-id" => nil},
          socket
        )

      assert result == socket
    end

    test "handles params without required keys", %{socket: socket} do
      {:noreply, result} = ConditionNode.handle_update_response_condition_builder(%{}, socket)
      assert result == socket
    end
  end

  # =============================================================================
  # handle_toggle_switch_mode/1
  # =============================================================================

  describe "handle_toggle_switch_mode/1" do
    setup :setup_condition_socket

    test "toggles switch_mode from false to true", %{socket: socket} do
      {:noreply, result} = ConditionNode.handle_toggle_switch_mode(socket)

      node = Storyarn.Flows.get_node!(result.assigns.flow.id, result.assigns.selected_node.id)
      assert node.data["switch_mode"] == true
    end

    test "toggles switch_mode from true to false", %{socket: socket, node: node} do
      Storyarn.Flows.update_node_data(node, Map.put(node.data, "switch_mode", true))

      {:noreply, result} = ConditionNode.handle_toggle_switch_mode(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert updated.data["switch_mode"] == false
    end

    test "adds labels to rules when enabling switch_mode", %{socket: socket, node: node} do
      condition = %{"logic" => "all", "rules" => [%{"variable" => "health"}]}

      Storyarn.Flows.update_node_data(
        node,
        node.data |> Map.put("condition", condition) |> Map.put("switch_mode", false)
      )

      {:noreply, result} = ConditionNode.handle_toggle_switch_mode(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      rules = updated.data["condition"]["rules"]
      # When enabling switch_mode, labels are added with default empty string
      assert length(rules) == 1
      assert hd(rules)["label"] == ""
    end

    test "does nothing when no condition node selected", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | selected_node: nil}}
      {:noreply, result} = ConditionNode.handle_toggle_switch_mode(socket)
      assert result == socket
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_condition_socket(_context) do
    project = project_fixture(user_fixture())
    flow = Storyarn.FlowsFixtures.flow_fixture(project)

    node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "condition",
        data: ConditionNode.default_data()
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
