defmodule StoryarnWeb.FlowLive.Nodes.Dialogue.NodeTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Nodes.Dialogue.Node, as: DialogueNode

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Metadata functions
  # =============================================================================

  describe "type/0" do
    test "returns dialogue" do
      assert DialogueNode.type() == "dialogue"
    end
  end

  describe "icon_name/0" do
    test "returns message-square" do
      assert DialogueNode.icon_name() == "message-square"
    end
  end

  describe "label/0" do
    test "returns Dialogue" do
      assert DialogueNode.label() == "Dialogue"
    end
  end

  # =============================================================================
  # default_data/0
  # =============================================================================

  describe "default_data/0" do
    test "returns map with expected keys" do
      data = DialogueNode.default_data()

      assert data["speaker_sheet_id"] == nil
      assert data["text"] == ""
      assert data["stage_directions"] == ""
      assert data["menu_text"] == ""
      assert data["audio_asset_id"] == nil
      assert data["technical_id"] == ""
      assert is_binary(data["localization_id"])
      assert data["localization_id"] =~ "dialogue."
      assert data["responses"] == []
    end

    test "generates unique localization_ids" do
      data1 = DialogueNode.default_data()
      data2 = DialogueNode.default_data()
      assert data1["localization_id"] != data2["localization_id"]
    end
  end

  # =============================================================================
  # extract_form_data/1
  # =============================================================================

  describe "extract_form_data/1" do
    test "extracts all dialogue fields from data" do
      data = %{
        "speaker_sheet_id" => 42,
        "text" => "<p>Hello</p>",
        "stage_directions" => "walks in",
        "menu_text" => "Greet",
        "audio_asset_id" => 7,
        "technical_id" => "dlg_test_1",
        "localization_id" => "dialogue.abc123",
        "responses" => [%{"id" => "r1", "text" => "Yes"}],
        "extra_field" => "ignored"
      }

      result = DialogueNode.extract_form_data(data)

      assert result["speaker_sheet_id"] == 42
      assert result["text"] == "<p>Hello</p>"
      assert result["stage_directions"] == "walks in"
      assert result["menu_text"] == "Greet"
      assert result["audio_asset_id"] == 7
      assert result["technical_id"] == "dlg_test_1"
      assert result["localization_id"] == "dialogue.abc123"
      assert result["responses"] == [%{"id" => "r1", "text" => "Yes"}]
      refute Map.has_key?(result, "extra_field")
    end

    test "provides defaults for missing fields" do
      result = DialogueNode.extract_form_data(%{})

      assert result["speaker_sheet_id"] == ""
      assert result["text"] == ""
      assert result["stage_directions"] == ""
      assert result["menu_text"] == ""
      assert result["audio_asset_id"] == nil
      assert result["technical_id"] == ""
      assert result["localization_id"] == ""
      assert result["responses"] == []
    end

    test "replaces nil values with defaults" do
      data = %{
        "speaker_sheet_id" => nil,
        "text" => nil,
        "audio_asset_id" => nil
      }

      result = DialogueNode.extract_form_data(data)

      assert result["speaker_sheet_id"] == ""
      assert result["text"] == ""
      assert result["audio_asset_id"] == nil
    end
  end

  # =============================================================================
  # on_select/2 and on_double_click/1
  # =============================================================================

  describe "on_select/2" do
    test "returns socket unchanged" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      assert DialogueNode.on_select(%{}, socket) == socket
    end
  end

  describe "on_double_click/1" do
    test "returns :editor" do
      assert DialogueNode.on_double_click(%{}) == :editor
    end
  end

  # =============================================================================
  # duplicate_data_cleanup/1
  # =============================================================================

  describe "duplicate_data_cleanup/1" do
    test "clears technical_id and generates new localization_id" do
      original_loc_id = "dialogue.original"

      data = %{
        "technical_id" => "dlg_test_1",
        "localization_id" => original_loc_id,
        "text" => "Keep this"
      }

      result = DialogueNode.duplicate_data_cleanup(data)

      assert result["technical_id"] == ""
      assert result["localization_id"] != original_loc_id
      assert result["localization_id"] =~ "dialogue."
      assert result["text"] == "Keep this"
    end
  end

  # =============================================================================
  # Response handlers
  # =============================================================================

  describe "handle_add_response/2" do
    setup :setup_dialogue_socket

    test "adds first response to a dialogue node", %{socket: socket, node: node} do
      {:noreply, result} =
        DialogueNode.handle_add_response(%{"node-id" => node.id}, socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert length(updated.data["responses"]) == 1

      response = hd(updated.data["responses"])
      assert is_binary(response["id"])
      assert response["id"] =~ "r1_"
      assert is_binary(response["text"])
      assert response["condition"] == nil
      assert response["instruction"] == nil
    end

    test "adds multiple responses", %{socket: socket, node: node} do
      {:noreply, socket1} =
        DialogueNode.handle_add_response(%{"node-id" => node.id}, socket)

      # Refresh socket with updated node
      updated_node = Storyarn.Flows.get_node!(socket1.assigns.flow.id, node.id)
      socket2 = %{socket1 | assigns: %{socket1.assigns | selected_node: updated_node}}

      {:noreply, result} =
        DialogueNode.handle_add_response(%{"node-id" => node.id}, socket2)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert length(updated.data["responses"]) == 2
    end
  end

  describe "handle_remove_response/2" do
    setup :setup_dialogue_with_responses

    test "removes a specific response", %{socket: socket, node: node, response_id: response_id} do
      {:noreply, result} =
        DialogueNode.handle_remove_response(
          %{"response-id" => response_id, "node-id" => node.id},
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      refute Enum.any?(updated.data["responses"], &(&1["id"] == response_id))
    end
  end

  describe "handle_update_response_text/1" do
    setup :setup_dialogue_with_responses

    test "updates response text", %{socket: socket, node: node, response_id: response_id} do
      {:noreply, result} =
        DialogueNode.handle_update_response_text(
          %{"response-id" => response_id, "node-id" => node.id, "value" => "Updated text"},
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      response = Enum.find(updated.data["responses"], &(&1["id"] == response_id))
      assert response["text"] == "Updated text"
    end
  end

  describe "handle_update_response_condition/1" do
    setup :setup_dialogue_with_responses

    test "sets response condition", %{socket: socket, node: node, response_id: response_id} do
      {:noreply, result} =
        DialogueNode.handle_update_response_condition(
          %{"response-id" => response_id, "node-id" => node.id, "value" => "health > 50"},
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      response = Enum.find(updated.data["responses"], &(&1["id"] == response_id))
      assert response["condition"] == "health > 50"
    end

    test "clears condition with empty string", %{
      socket: socket,
      node: node,
      response_id: response_id
    } do
      {:noreply, result} =
        DialogueNode.handle_update_response_condition(
          %{"response-id" => response_id, "node-id" => node.id, "value" => ""},
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      response = Enum.find(updated.data["responses"], &(&1["id"] == response_id))
      assert response["condition"] == nil
    end
  end

  describe "handle_update_response_instruction/1" do
    setup :setup_dialogue_with_responses

    test "sets response instruction", %{socket: socket, node: node, response_id: response_id} do
      {:noreply, result} =
        DialogueNode.handle_update_response_instruction(
          %{"response-id" => response_id, "node-id" => node.id, "value" => "set health = 100"},
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      response = Enum.find(updated.data["responses"], &(&1["id"] == response_id))
      assert response["instruction"] == "set health = 100"
    end

    test "clears instruction with empty string", %{
      socket: socket,
      node: node,
      response_id: response_id
    } do
      {:noreply, result} =
        DialogueNode.handle_update_response_instruction(
          %{"response-id" => response_id, "node-id" => node.id, "value" => ""},
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      response = Enum.find(updated.data["responses"], &(&1["id"] == response_id))
      assert response["instruction"] == nil
    end
  end

  describe "handle_update_response_instruction_builder/1" do
    setup :setup_dialogue_with_responses

    test "sets structured assignments", %{socket: socket, node: node, response_id: response_id} do
      assignments = [%{"variable" => "health", "operator" => "set", "value" => "100"}]

      {:noreply, result} =
        DialogueNode.handle_update_response_instruction_builder(
          %{
            "assignments" => assignments,
            "response-id" => response_id,
            "node-id" => node.id
          },
          socket
        )

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      response = Enum.find(updated.data["responses"], &(&1["id"] == response_id))
      assert length(response["instruction_assignments"]) == 1
      assert hd(response["instruction_assignments"])["variable"] == "health"
      assert hd(response["instruction_assignments"])["operator"] == "set"
    end
  end

  # =============================================================================
  # Technical ID generation
  # =============================================================================

  describe "handle_generate_technical_id/1" do
    setup :setup_dialogue_socket

    test "generates technical ID with narrator when no speaker", %{socket: socket, node: node} do
      {:noreply, result} = DialogueNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert updated.data["technical_id"] =~ "narrator"
    end

    test "generates technical ID using speaker name", %{socket: socket, project: project} do
      sheet = Storyarn.SheetsFixtures.sheet_fixture(project, %{name: "Jaime"})

      # Update node to have speaker_sheet_id
      node = socket.assigns.selected_node

      {:ok, updated_node, _} =
        Storyarn.Flows.update_node_data(
          node,
          Map.put(node.data, "speaker_sheet_id", sheet.id)
        )

      socket = %{
        socket
        | assigns: %{socket.assigns | all_sheets: [sheet], selected_node: updated_node}
      }

      {:noreply, result} = DialogueNode.handle_generate_technical_id(socket)

      updated = Storyarn.Flows.get_node!(result.assigns.flow.id, node.id)
      assert updated.data["technical_id"] =~ "jaime"
    end
  end

  # =============================================================================
  # handle_open_screenplay/1
  # =============================================================================

  describe "handle_open_screenplay/1" do
    setup :setup_dialogue_socket

    test "sets editing_mode to :editor when dialogue node selected", %{socket: socket} do
      {:noreply, result} = DialogueNode.handle_open_screenplay(socket)
      assert result.assigns.editing_mode == :editor
    end

    test "does nothing when no dialogue node selected", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | selected_node: nil}}
      {:noreply, result} = DialogueNode.handle_open_screenplay(socket)
      refute Map.has_key?(result.assigns, :editing_mode)
    end

    test "does nothing when non-dialogue node selected", %{socket: socket} do
      non_dialogue = %{socket.assigns.selected_node | type: "condition"}
      socket = %{socket | assigns: %{socket.assigns | selected_node: non_dialogue}}
      {:noreply, result} = DialogueNode.handle_open_screenplay(socket)
      refute Map.has_key?(result.assigns, :editing_mode)
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_dialogue_socket(_context) do
    project = project_fixture(user_fixture())
    flow = Storyarn.FlowsFixtures.flow_fixture(project)

    node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "dialogue",
        data: DialogueNode.default_data()
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

  defp setup_dialogue_with_responses(_context) do
    %{flow: flow, socket: socket, project: project, node: node} =
      setup_dialogue_socket(%{})

    # Add a response manually via the DB
    response_id = "r1_#{:erlang.unique_integer([:positive])}"

    responses = [
      %{
        "id" => response_id,
        "text" => "Initial response",
        "condition" => nil,
        "instruction" => nil,
        "instruction_assignments" => []
      }
    ]

    {:ok, updated_node, _} =
      Storyarn.Flows.update_node_data(
        node,
        Map.put(node.data, "responses", responses)
      )

    socket = %{socket | assigns: %{socket.assigns | selected_node: updated_node}}

    %{
      flow: flow,
      socket: socket,
      project: project,
      node: updated_node,
      response_id: response_id
    }
  end
end
