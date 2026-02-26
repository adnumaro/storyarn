defmodule StoryarnWeb.FlowLive.Nodes.Hub.NodeTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Nodes.Hub.Node, as: HubNode

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Metadata functions
  # =============================================================================

  describe "type/0" do
    test "returns hub" do
      assert HubNode.type() == "hub"
    end
  end

  describe "icon_name/0" do
    test "returns log-in" do
      assert HubNode.icon_name() == "log-in"
    end
  end

  describe "label/0" do
    test "returns non-empty Hub label" do
      label = HubNode.label()
      assert is_binary(label)
      assert label != ""
      assert label == "Hub"
    end
  end

  # =============================================================================
  # default_data/0
  # =============================================================================

  describe "default_data/0" do
    test "returns map with hub_id, label, color" do
      data = HubNode.default_data()
      assert data["hub_id"] == ""
      assert data["label"] == ""
      assert data["color"] == "#8b5cf6"
    end
  end

  # =============================================================================
  # extract_form_data/1
  # =============================================================================

  describe "extract_form_data/1" do
    test "extracts hub fields from data" do
      data = %{
        "hub_id" => "hub_1",
        "label" => "Checkpoint",
        "color" => "#FF0000",
        "extra" => "ignored"
      }

      result = HubNode.extract_form_data(data)

      assert result["hub_id"] == "hub_1"
      assert result["label"] == "Checkpoint"
      assert result["color"] == "#FF0000"
      refute Map.has_key?(result, "extra")
    end

    test "provides defaults for missing fields" do
      data = %{}
      result = HubNode.extract_form_data(data)

      assert result["hub_id"] == ""
      assert result["label"] == ""
      assert result["color"] == "#8b5cf6"
    end

    test "handles nil values with defaults" do
      data = %{"hub_id" => nil, "label" => nil, "color" => nil}
      result = HubNode.extract_form_data(data)

      assert result["hub_id"] == ""
      assert result["label"] == ""
      assert result["color"] == "#8b5cf6"
    end
  end

  # =============================================================================
  # on_double_click/1
  # =============================================================================

  describe "on_double_click/1" do
    test "returns :toolbar" do
      assert HubNode.on_double_click(%{}) == :toolbar
    end
  end

  # =============================================================================
  # duplicate_data_cleanup/1
  # =============================================================================

  describe "duplicate_data_cleanup/1" do
    test "clears hub_id" do
      data = %{"hub_id" => "hub_123", "label" => "Keep", "color" => "#FF0000"}
      result = HubNode.duplicate_data_cleanup(data)

      assert result["hub_id"] == ""
      assert result["label"] == "Keep"
      assert result["color"] == "#FF0000"
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

    test "assigns empty referencing_jumps when no jumps reference the hub", %{socket: socket} do
      node = %{data: %{"hub_id" => "hub_nonexistent"}}
      result = HubNode.on_select(node, socket)

      assert result.assigns.referencing_jumps == []
    end

    test "assigns referencing_jumps when jump nodes target the hub", %{flow: flow, socket: socket} do
      hub_id = "hub_test_#{System.unique_integer([:positive])}"

      # Create a hub node
      _hub =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => hub_id, "label" => "Test Hub", "color" => "#8b5cf6"}
        })

      # Create jump nodes referencing this hub
      jump1 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "jump",
          position_x: 200.0,
          position_y: 100.0,
          data: %{"target_hub_id" => hub_id}
        })

      jump2 =
        Storyarn.FlowsFixtures.node_fixture(flow, %{
          type: "jump",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"target_hub_id" => hub_id}
        })

      node = %{data: %{"hub_id" => hub_id}}
      result = HubNode.on_select(node, socket)

      jump_ids = Enum.map(result.assigns.referencing_jumps, & &1.id)
      assert jump1.id in jump_ids
      assert jump2.id in jump_ids
      assert length(result.assigns.referencing_jumps) == 2
    end

    test "handles nil hub_id gracefully", %{socket: socket} do
      node = %{data: %{"hub_id" => nil}}
      result = HubNode.on_select(node, socket)

      assert result.assigns.referencing_jumps == []
    end

    test "handles missing hub_id key gracefully", %{socket: socket} do
      node = %{data: %{}}
      result = HubNode.on_select(node, socket)

      assert result.assigns.referencing_jumps == []
    end
  end
end
