defmodule StoryarnWeb.FlowLive.Nodes.Scene.NodeTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Nodes.Scene.Node, as: SceneNode

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Metadata functions
  # =============================================================================

  describe "type/0" do
    test "returns scene" do
      assert SceneNode.type() == "scene"
    end
  end

  describe "icon_name/0" do
    test "returns clapperboard" do
      assert SceneNode.icon_name() == "clapperboard"
    end
  end

  describe "label/0" do
    test "returns Scene" do
      assert SceneNode.label() == "Scene"
    end
  end

  # =============================================================================
  # default_data/0
  # =============================================================================

  describe "default_data/0" do
    test "returns map with expected keys and defaults" do
      data = SceneNode.default_data()

      assert data["location_sheet_id"] == nil
      assert data["int_ext"] == "int"
      assert data["sub_location"] == ""
      assert data["time_of_day"] == ""
      assert data["description"] == ""
      assert data["technical_id"] == ""
    end
  end

  # =============================================================================
  # extract_form_data/1
  # =============================================================================

  describe "extract_form_data/1" do
    test "extracts all scene fields from data" do
      data = %{
        "location_sheet_id" => 42,
        "int_ext" => "ext",
        "sub_location" => "Garden",
        "time_of_day" => "Night",
        "description" => "A dark garden",
        "technical_id" => "scene_ext_garden_1",
        "extra" => "ignored"
      }

      result = SceneNode.extract_form_data(data)

      assert result["location_sheet_id"] == 42
      assert result["int_ext"] == "ext"
      assert result["sub_location"] == "Garden"
      assert result["time_of_day"] == "Night"
      assert result["description"] == "A dark garden"
      assert result["technical_id"] == "scene_ext_garden_1"
      refute Map.has_key?(result, "extra")
    end

    test "provides defaults for missing fields" do
      result = SceneNode.extract_form_data(%{})

      assert result["location_sheet_id"] == ""
      assert result["int_ext"] == "int"
      assert result["sub_location"] == ""
      assert result["time_of_day"] == ""
      assert result["description"] == ""
      assert result["technical_id"] == ""
    end
  end

  # =============================================================================
  # on_select/2, on_double_click/1, duplicate_data_cleanup/1
  # =============================================================================

  describe "on_select/2" do
    test "returns socket unchanged" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      assert SceneNode.on_select(%{}, socket) == socket
    end
  end

  describe "on_double_click/1" do
    test "returns :toolbar" do
      assert SceneNode.on_double_click(%{}) == :toolbar
    end
  end

  describe "duplicate_data_cleanup/1" do
    test "clears technical_id" do
      data = %{
        "technical_id" => "scene_int_castle_1",
        "int_ext" => "int",
        "description" => "Keep"
      }

      result = SceneNode.duplicate_data_cleanup(data)

      assert result["technical_id"] == ""
      assert result["int_ext"] == "int"
      assert result["description"] == "Keep"
    end
  end

  # =============================================================================
  # handle_generate_technical_id/1
  # =============================================================================

  describe "handle_generate_technical_id/1" do
    setup :setup_scene_socket

    test "generates technical ID with int_ext and location defaults", %{
      socket: socket,
      node: node
    } do
      {:noreply, result} = SceneNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert updated.data["technical_id"] =~ "int"
      assert updated.data["technical_id"] =~ "location"
    end

    test "generates technical ID using location sheet name", %{
      socket: socket,
      project: project,
      node: node
    } do
      sheet = Storyarn.SheetsFixtures.sheet_fixture(project, %{name: "Castle"})

      {:ok, updated_node, _} =
        Storyarn.Flows.update_node_data(
          node,
          node.data
          |> Map.put("location_sheet_id", sheet.id)
          |> Map.put("int_ext", "ext")
        )

      socket = %{
        socket
        | assigns: %{socket.assigns | all_sheets: [sheet], selected_node: updated_node}
      }

      {:noreply, result} = SceneNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert updated.data["technical_id"] =~ "ext"
      assert updated.data["technical_id"] =~ "castle"
    end

    test "includes scene count in technical ID", %{socket: socket, flow: flow, node: node} do
      # Create another scene node first
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "scene",
        data: SceneNode.default_data()
      })

      {:noreply, result} = SceneNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      # Should end with a number
      assert updated.data["technical_id"] =~ ~r/_\d+$/
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_scene_socket(_context) do
    project = project_fixture(user_fixture())
    flow = Storyarn.FlowsFixtures.flow_fixture(project)

    node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "scene",
        data: SceneNode.default_data()
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
        save_status: :idle,
        all_sheets: []
      },
      private: %{lifecycle_events: [], live_temp: %{}}
    }

    %{flow: flow, socket: socket, project: project, node: node}
  end
end
