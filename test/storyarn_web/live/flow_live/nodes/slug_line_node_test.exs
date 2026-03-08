defmodule StoryarnWeb.FlowLive.Nodes.SlugLine.NodeTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Nodes.SlugLine.Node, as: SlugLineNode

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Metadata functions
  # =============================================================================

  describe "type/0" do
    test "returns slug_line" do
      assert SlugLineNode.type() == "slug_line"
    end
  end

  describe "icon_name/0" do
    test "returns clapperboard" do
      assert SlugLineNode.icon_name() == "clapperboard"
    end
  end

  describe "label/0" do
    test "returns Slug Line" do
      assert SlugLineNode.label() == "Slug Line"
    end
  end

  # =============================================================================
  # default_data/0
  # =============================================================================

  describe "default_data/0" do
    test "returns map with expected keys and defaults" do
      data = SlugLineNode.default_data()

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
    test "extracts all slug line fields from data" do
      data = %{
        "location_sheet_id" => 42,
        "int_ext" => "ext",
        "sub_location" => "Garden",
        "time_of_day" => "Night",
        "description" => "A dark garden",
        "technical_id" => "slug_ext_garden_1",
        "extra" => "ignored"
      }

      result = SlugLineNode.extract_form_data(data)

      assert result["location_sheet_id"] == 42
      assert result["int_ext"] == "ext"
      assert result["sub_location"] == "Garden"
      assert result["time_of_day"] == "Night"
      assert result["description"] == "A dark garden"
      assert result["technical_id"] == "slug_ext_garden_1"
      refute Map.has_key?(result, "extra")
    end

    test "provides defaults for missing fields" do
      result = SlugLineNode.extract_form_data(%{})

      assert result["location_sheet_id"] == ""
      assert result["int_ext"] == "int"
      assert result["sub_location"] == ""
      assert result["time_of_day"] == ""
      assert result["description"] == ""
      assert result["technical_id"] == ""
    end
  end

  # =============================================================================
  # duplicate_data_cleanup/1
  # =============================================================================

  describe "duplicate_data_cleanup/1" do
    test "clears technical_id" do
      data = %{
        "technical_id" => "slug_int_castle_1",
        "int_ext" => "int",
        "description" => "Keep"
      }

      result = SlugLineNode.duplicate_data_cleanup(data)

      assert result["technical_id"] == ""
      assert result["int_ext"] == "int"
      assert result["description"] == "Keep"
    end
  end

  # =============================================================================
  # handle_generate_technical_id/1
  # =============================================================================

  describe "handle_generate_technical_id/1" do
    setup :setup_slug_line_socket

    test "generates technical ID with int_ext and location defaults", %{
      socket: socket,
      node: node
    } do
      {:noreply, result} = SlugLineNode.handle_generate_technical_id(socket)

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

      {:noreply, result} = SlugLineNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert updated.data["technical_id"] =~ "ext"
      assert updated.data["technical_id"] =~ "castle"
    end

    test "includes slug line count in technical ID", %{socket: socket, flow: flow, node: node} do
      # Create another slug line node first
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "slug_line",
        data: SlugLineNode.default_data()
      })

      {:noreply, result} = SlugLineNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      # Should end with a number
      assert updated.data["technical_id"] =~ ~r/_\d+$/
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_slug_line_socket(_context) do
    user = user_fixture()
    project = project_fixture(user)
    flow = Storyarn.FlowsFixtures.flow_fixture(project)

    node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "slug_line",
        data: SlugLineNode.default_data()
      })

    flow = Storyarn.Flows.get_flow!(project.id, flow.id)
    flow_data = Storyarn.Flows.serialize_for_canvas(flow)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        flow: flow,
        project: project,
        current_scope: %{user: user},
        node_form: nil,
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
