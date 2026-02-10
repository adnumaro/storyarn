defmodule Storyarn.Screenplays.FlowSyncTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.FlowSync

  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_project(_context) do
    project = project_fixture()
    %{project: project}
  end

  describe "ensure_flow/1" do
    setup :setup_project

    test "creates a new flow when screenplay is unlinked", %{project: project} do
      screenplay = screenplay_fixture(project)
      assert is_nil(screenplay.linked_flow_id)

      {:ok, flow} = FlowSync.ensure_flow(screenplay)

      assert flow.id
      assert flow.name == screenplay.name

      # Screenplay should now be linked
      updated = Screenplays.get_screenplay!(project.id, screenplay.id)
      assert updated.linked_flow_id == flow.id
    end

    test "returns existing flow when screenplay is linked", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = FlowSync.ensure_flow(screenplay)

      # Re-fetch screenplay with the link
      screenplay = Screenplays.get_screenplay!(project.id, screenplay.id)
      {:ok, same_flow} = FlowSync.ensure_flow(screenplay)

      assert same_flow.id == flow.id
    end
  end

  describe "link_to_flow/2" do
    setup :setup_project

    test "links screenplay to an existing flow", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Target Flow"})

      {:ok, updated} = FlowSync.link_to_flow(screenplay, flow.id)

      assert updated.linked_flow_id == flow.id
    end

    test "rejects linking to flow from different project", %{project: _project} do
      other_project = project_fixture()
      screenplay = screenplay_fixture(other_project)

      # Create flow in a DIFFERENT project
      yet_another_project = project_fixture()
      {:ok, flow} = Flows.create_flow(yet_another_project, %{name: "Other Flow"})

      assert {:error, :flow_not_found} = FlowSync.link_to_flow(screenplay, flow.id)
    end
  end

  describe "unlink_flow/1" do
    setup :setup_project

    test "clears linked_flow_id and all linked_node_ids", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = FlowSync.ensure_flow(screenplay)
      screenplay = Screenplays.get_screenplay!(project.id, screenplay.id)

      # Reload flow with preloads to access nodes
      flow = Flows.get_flow!(project.id, flow.id)
      entry_node = Enum.find(flow.nodes, &(&1.type == "entry"))
      element = element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE"})

      Storyarn.Repo.update!(
        Storyarn.Screenplays.ScreenplayElement.link_node_changeset(element, %{linked_node_id: entry_node.id})
      )

      {:ok, unlinked} = FlowSync.unlink_flow(screenplay)

      assert is_nil(unlinked.linked_flow_id)

      # Element should have nil linked_node_id
      [refreshed_element] = Screenplays.list_elements(screenplay.id)
      assert is_nil(refreshed_element.linked_node_id)
    end

    test "is a no-op when already unlinked", %{project: project} do
      screenplay = screenplay_fixture(project)
      assert is_nil(screenplay.linked_flow_id)

      {:ok, same} = FlowSync.unlink_flow(screenplay)
      assert is_nil(same.linked_flow_id)
    end
  end

  describe "sync_to_flow/1" do
    setup :setup_project

    test "creates nodes from screenplay elements", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "A desk sits in the corner.", position: 1})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      synced = Flows.list_nodes(flow.id) |> Enum.filter(&(&1.source == "screenplay_sync"))

      assert length(synced) == 2
      assert Enum.any?(synced, &(&1.type == "entry"))
      assert Enum.any?(synced, &(&1.type == "dialogue"))
    end

    test "creates sequential connections between nodes", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})
      element_fixture(screenplay, %{type: "character", content: "JOHN", position: 2})
      element_fixture(screenplay, %{type: "dialogue", content: "Hello.", position: 3})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      connections = Flows.list_connections(flow.id)

      # entry → action_dialogue, action_dialogue → char+dialogue = 2 connections
      assert length(connections) == 2
      assert Enum.all?(connections, &(&1.source_pin == "output"))
      assert Enum.all?(connections, &(&1.target_pin == "input"))
    end

    test "updates existing synced nodes on re-sync preserving position", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      action = element_fixture(screenplay, %{type: "action", content: "Original.", position: 1})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)

      # Move the synced dialogue node
      synced_dialogue =
        Flows.list_nodes(flow.id)
        |> Enum.find(&(&1.type == "dialogue" and &1.source == "screenplay_sync"))

      Flows.update_node_position(synced_dialogue, %{position_x: 999.0, position_y: 888.0})

      # Update element content and re-sync
      Screenplays.update_element(action, %{content: "Updated."})
      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)

      updated = Flows.list_nodes(flow.id) |> Enum.find(&(&1.id == synced_dialogue.id))
      assert updated.data["stage_directions"] == "Updated."
      assert updated.position_x == 999.0
      assert updated.position_y == 888.0
    end

    test "deletes orphaned synced nodes", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      action = element_fixture(screenplay, %{type: "action", content: "To remove.", position: 1})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      assert 2 == Flows.list_nodes(flow.id) |> Enum.count(&(&1.source == "screenplay_sync"))

      Screenplays.delete_element(action)
      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)

      synced = Flows.list_nodes(flow.id) |> Enum.filter(&(&1.source == "screenplay_sync"))
      assert length(synced) == 1
      assert hd(synced).type == "entry"
    end

    test "never touches manual nodes", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      {:ok, manual} = Flows.create_node(flow, %{type: "dialogue", data: %{}})

      # Re-sync
      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)

      assert Flows.get_node(flow.id, manual.id) != nil
    end

    test "links elements to created nodes via linked_node_id", %{project: project} do
      screenplay = screenplay_fixture(project)
      sh = element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      act = element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})

      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      sh_el = Enum.find(elements, &(&1.id == sh.id))
      act_el = Enum.find(elements, &(&1.id == act.id))

      refute is_nil(sh_el.linked_node_id)
      refute is_nil(act_el.linked_node_id)
      assert sh_el.linked_node_id != act_el.linked_node_id
    end

    test "handles dialogue group with response choices", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "character", content: "NPC", position: 1})
      element_fixture(screenplay, %{type: "dialogue", content: "What do you want?", position: 2})

      element_fixture(screenplay, %{
        type: "response",
        position: 3,
        data: %{
          "choices" => [
            %{"id" => "c1", "text" => "Help"},
            %{"id" => "c2", "text" => "Nothing"}
          ]
        }
      })

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      synced = Flows.list_nodes(flow.id) |> Enum.filter(&(&1.source == "screenplay_sync"))
      dialogue = Enum.find(synced, &(&1.type == "dialogue"))

      assert dialogue.data["text"] == "What do you want?"
      assert length(dialogue.data["responses"]) == 2
    end

    test "skips non-mappeable elements", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "note", content: "Remember to revise", position: 1})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 2})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      synced = Flows.list_nodes(flow.id) |> Enum.filter(&(&1.source == "screenplay_sync"))

      assert length(synced) == 2
      types = Enum.map(synced, & &1.type) |> Enum.sort()
      assert types == ["dialogue", "entry"]
    end

    test "empty screenplay syncs without creating synced nodes", %{project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      nodes = Flows.list_nodes(flow.id)

      # Only auto-created entry + exit from create_flow (both manual)
      assert length(nodes) == 2
      assert Enum.all?(nodes, &(&1.source == "manual"))
    end

    test "handles orphan response creating dialogue wrapper", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})

      element_fixture(screenplay, %{
        type: "response",
        position: 1,
        data: %{"choices" => [%{"id" => "c1", "text" => "Option A"}]}
      })

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      synced = Flows.list_nodes(flow.id) |> Enum.filter(&(&1.source == "screenplay_sync"))
      dialogue = Enum.find(synced, &(&1.type == "dialogue"))

      assert dialogue.data["text"] == ""
      assert length(dialogue.data["responses"]) == 1
    end

    test "condition node gets both true and false connections to next node", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})

      element_fixture(screenplay, %{
        type: "conditional",
        position: 1,
        data: %{"condition" => %{"logic" => "all", "rules" => []}}
      })

      element_fixture(screenplay, %{type: "action", content: "Next.", position: 2})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)
      connections = Flows.list_connections(flow.id)

      # entry→condition (output), condition→dialogue (true), condition→dialogue (false) = 3
      assert length(connections) == 3

      condition_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "condition"))
      condition_conns = Enum.filter(connections, &(&1.source_node_id == condition_node.id))
      assert length(condition_conns) == 2
      pins = Enum.map(condition_conns, & &1.source_pin) |> Enum.sort()
      assert pins == ["false", "true"]
    end
  end

  describe "sync_from_flow/1" do
    setup :setup_project

    test "returns error when screenplay is not linked", %{project: project} do
      screenplay = screenplay_fixture(project)

      assert {:error, :not_linked} = FlowSync.sync_from_flow(screenplay)
    end

    test "returns error when flow has no entry node", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Empty Flow"})
      {:ok, screenplay} = FlowSync.link_to_flow(screenplay, flow.id)

      # Delete default entry node
      entry = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      # Force delete entry by deleting from DB directly
      Storyarn.Repo.delete!(entry)

      assert {:error, :no_entry_node} = FlowSync.sync_from_flow(screenplay)
    end

    test "creates elements from flow nodes", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})

      # Push to flow first
      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)

      # Delete screenplay elements to simulate empty screenplay
      Screenplays.list_elements(screenplay.id) |> Enum.each(&Storyarn.Repo.delete!/1)
      assert Screenplays.list_elements(screenplay.id) == []

      # Pull from flow
      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      types = Enum.map(elements, & &1.type)

      # entry → scene_heading, dialogue(action) → action
      assert "scene_heading" in types
      assert "action" in types
    end

    test "dialogue node with text produces character + dialogue elements", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = FlowSync.ensure_flow(screenplay)
      screenplay = Screenplays.get_screenplay!(project.id, screenplay.id)

      # Create a dialogue node manually on the flow
      {:ok, _node} =
        Flows.create_node(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello there.",
            "stage_directions" => "",
            "menu_text" => "JOHN",
            "responses" => []
          }
        })

      # Connect entry → dialogue
      entry = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      dialogue = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "dialogue"))

      Flows.create_connection(flow, entry, dialogue, %{
        source_pin: "output",
        target_pin: "input"
      })

      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      types = Enum.map(elements, & &1.type)

      assert "scene_heading" in types
      assert "character" in types
      assert "dialogue" in types

      char = Enum.find(elements, &(&1.type == "character"))
      assert char.content == "JOHN"

      dlg = Enum.find(elements, &(&1.type == "dialogue"))
      assert dlg.content == "Hello there."
    end

    test "action-style dialogue produces single action element", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = FlowSync.ensure_flow(screenplay)
      screenplay = Screenplays.get_screenplay!(project.id, screenplay.id)

      {:ok, _node} =
        Flows.create_node(flow, %{
          type: "dialogue",
          data: %{
            "text" => "",
            "stage_directions" => "A desk sits in the corner.",
            "menu_text" => "",
            "responses" => []
          }
        })

      entry = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      action_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "dialogue" and &1.source == "manual"))
      Flows.create_connection(flow, entry, action_node, %{source_pin: "output", target_pin: "input"})

      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      action = Enum.find(elements, &(&1.type == "action"))

      assert action
      assert action.content == "A desk sits in the corner."
    end

    test "updates existing linked elements on re-sync", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "Original.", position: 1})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)

      # Modify flow node data
      dialogue_node =
        Flows.list_nodes(flow.id)
        |> Enum.find(&(&1.type == "dialogue" and &1.data["stage_directions"] == "Original."))

      Flows.update_node(dialogue_node, %{data: Map.put(dialogue_node.data, "stage_directions", "Updated from flow.")})

      # Pull back
      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      action = Enum.find(elements, &(&1.type == "action"))

      assert action.content == "Updated from flow."
    end

    test "deletes orphaned mappeable elements on re-sync", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "To remove.", position: 1})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)

      # Delete the dialogue node from flow (the action-mapped one)
      dialogue_node =
        Flows.list_nodes(flow.id)
        |> Enum.find(&(&1.type == "dialogue" and &1.data["stage_directions"] == "To remove."))

      # Also delete associated connections
      Flows.list_connections(flow.id)
      |> Enum.filter(&(&1.source_node_id == dialogue_node.id or &1.target_node_id == dialogue_node.id))
      |> Enum.each(&Storyarn.Repo.delete!/1)

      Storyarn.Repo.delete!(dialogue_node)

      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      types = Enum.map(elements, & &1.type)

      assert "scene_heading" in types
      refute "action" in types
    end

    test "preserves non-mappeable elements (notes)", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "note", content: "Remember to revise", position: 1})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 2})

      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)

      # Sync from flow — note should survive
      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      types = Enum.map(elements, & &1.type)

      assert "note" in types
      note = Enum.find(elements, &(&1.type == "note"))
      assert note.content == "Remember to revise"
    end

    test "non-mappeable element position anchored to next mapped element", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "note", content: "My note", position: 1})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 2})

      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)
      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      note = Enum.find(elements, &(&1.type == "note"))
      action = Enum.find(elements, &(&1.type == "action"))

      # Note should be before the action element it was anchored to
      assert note.position < action.position
    end

    test "elements get linked_node_id set after sync", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = FlowSync.ensure_flow(screenplay)
      screenplay = Screenplays.get_screenplay!(project.id, screenplay.id)

      {:ok, _node} =
        Flows.create_node(flow, %{
          type: "dialogue",
          data: %{"text" => "Hi.", "stage_directions" => "", "menu_text" => "BOB", "responses" => []}
        })

      entry = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      dialogue = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "dialogue"))
      Flows.create_connection(flow, entry, dialogue, %{source_pin: "output", target_pin: "input"})

      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      mappeable = Enum.reject(elements, &(&1.type in Storyarn.Screenplays.ScreenplayElement.non_mappeable_types()))

      assert Enum.all?(mappeable, &(not is_nil(&1.linked_node_id)))
    end

    test "subflow nodes are skipped", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = FlowSync.ensure_flow(screenplay)
      screenplay = Screenplays.get_screenplay!(project.id, screenplay.id)

      {:ok, _node} = Flows.create_node(flow, %{type: "subflow", data: %{}})

      entry = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      subflow = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "subflow"))
      Flows.create_connection(flow, entry, subflow, %{source_pin: "output", target_pin: "input"})

      {:ok, _screenplay} = FlowSync.sync_from_flow(screenplay)

      elements = Screenplays.list_elements(screenplay.id)
      types = Enum.map(elements, & &1.type)

      # Only scene_heading from entry, no subflow element
      assert "scene_heading" in types
      refute "subflow" in types
      assert length(elements) == 1
    end
  end

  describe "sync_to_flow/1 auto-layout" do
    setup :setup_project

    test "positions new nodes at x=400 with 150px vertical spacing", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Line one.", position: 0})
      element_fixture(screenplay, %{type: "action", content: "Line two.", position: 1})
      element_fixture(screenplay, %{type: "action", content: "Line three.", position: 2})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)

      synced =
        Flows.list_nodes(flow.id)
        |> Enum.filter(&(&1.source == "screenplay_sync"))
        |> Enum.sort_by(& &1.position_y)

      assert length(synced) == 3
      [first, second, third] = synced
      assert first.position_x == 400.0
      assert first.position_y == 100.0
      assert second.position_y == 250.0
      assert third.position_y == 400.0
    end

    test "entry node preserves its create_flow position", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)

      entry =
        Flows.list_nodes(flow.id)
        |> Enum.find(&(&1.type == "entry"))

      # Entry was created by create_flow at (100, 300), preserved during sync
      assert entry.position_x == 100.0
      assert entry.position_y == 300.0

      # New dialogue node gets auto-layout at index 1
      dialogue =
        Flows.list_nodes(flow.id)
        |> Enum.find(&(&1.type == "dialogue" and &1.source == "screenplay_sync"))

      assert dialogue.position_x == 400.0
      assert dialogue.position_y == 250.0
    end

    test "re-sync only auto-positions newly created nodes", %{project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})

      {:ok, flow} = FlowSync.sync_to_flow(screenplay)

      # Move existing dialogue node manually
      action_dialogue =
        Flows.list_nodes(flow.id)
        |> Enum.find(&(&1.type == "dialogue" and &1.source == "screenplay_sync"))

      Flows.update_node_position(action_dialogue, %{position_x: 800.0, position_y: 500.0})

      # Add new elements and re-sync
      element_fixture(screenplay, %{type: "character", content: "BOB", position: 2})
      element_fixture(screenplay, %{type: "dialogue", content: "Hi.", position: 3})
      {:ok, _flow} = FlowSync.sync_to_flow(screenplay)

      nodes = Flows.list_nodes(flow.id) |> Enum.filter(&(&1.source == "screenplay_sync"))

      # Existing dialogue keeps manually moved position
      existing = Enum.find(nodes, &(&1.id == action_dialogue.id))
      assert existing.position_x == 800.0
      assert existing.position_y == 500.0

      # New dialogue gets auto-positioned at index 2
      new_dialogue =
        Enum.find(nodes, &(&1.type == "dialogue" and &1.id != action_dialogue.id))

      assert new_dialogue.position_x == 400.0
      assert new_dialogue.position_y == 400.0
    end
  end
end
