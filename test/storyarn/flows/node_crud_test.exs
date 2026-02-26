defmodule Storyarn.Flows.NodeCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  # ===========================================================================
  # Setup helpers
  # ===========================================================================

  defp create_project_and_flow(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{user: user, project: project, flow: flow}
  end

  defp get_entry_node(flow) do
    Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
  end

  defp get_exit_node(flow) do
    Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))
  end

  # ===========================================================================
  # Query helpers
  # ===========================================================================

  describe "list_nodes/1" do
    test "returns all non-deleted nodes for a flow" do
      %{flow: flow} = create_project_and_flow()

      node1 = node_fixture(flow, %{type: "dialogue"})
      node2 = node_fixture(flow, %{type: "condition"})

      nodes = Flows.list_nodes(flow.id)

      # 2 auto-created (entry + exit) + 2 manually created = 4
      assert length(nodes) == 4
      assert Enum.any?(nodes, &(&1.id == node1.id))
      assert Enum.any?(nodes, &(&1.id == node2.id))
    end

    test "excludes soft-deleted nodes" do
      %{flow: flow} = create_project_and_flow()

      node = node_fixture(flow, %{type: "dialogue"})
      Flows.delete_node(node)

      nodes = Flows.list_nodes(flow.id)
      refute Enum.any?(nodes, &(&1.id == node.id))
    end

    test "returns nodes ordered by insertion time" do
      %{flow: flow} = create_project_and_flow()

      node1 = node_fixture(flow, %{type: "dialogue"})
      node2 = node_fixture(flow, %{type: "condition"})

      nodes = Flows.list_nodes(flow.id)
      node_ids = Enum.map(nodes, & &1.id)

      # Both manually created nodes appear in the list
      assert node1.id in node_ids
      assert node2.id in node_ids

      # Auto-created nodes (entry/exit) have earlier IDs than manually created ones
      entry = Enum.find(nodes, &(&1.type == "entry"))
      assert entry.id < node1.id
      assert entry.id < node2.id
    end

    test "returns empty list for nonexistent flow" do
      assert Flows.list_nodes(-1) == []
    end
  end

  describe "get_node/2" do
    test "returns node with connections preloaded" do
      %{flow: flow} = create_project_and_flow()

      node1 = node_fixture(flow, %{type: "dialogue"})
      node2 = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, node1, node2)

      result = Flows.get_node(flow.id, node1.id)

      assert result.id == node1.id
      assert Ecto.assoc_loaded?(result.outgoing_connections)
      assert Ecto.assoc_loaded?(result.incoming_connections)
      assert length(result.outgoing_connections) == 1
    end

    test "returns nil for non-existent node" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.get_node(flow.id, -1) == nil
    end

    test "returns nil for deleted node" do
      %{flow: flow} = create_project_and_flow()

      node = node_fixture(flow, %{type: "dialogue"})
      Flows.delete_node(node)

      assert Flows.get_node(flow.id, node.id) == nil
    end

    test "returns nil when node belongs to different flow" do
      %{project: project, flow: flow1} = create_project_and_flow()
      flow2 = flow_fixture(project, %{name: "Other flow"})
      node = node_fixture(flow2, %{type: "dialogue"})

      assert Flows.get_node(flow1.id, node.id) == nil
    end
  end

  describe "get_node!/2" do
    test "returns node when it exists" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      result = Flows.get_node!(flow.id, node.id)
      assert result.id == node.id
    end

    test "raises for non-existent node" do
      %{flow: flow} = create_project_and_flow()

      assert_raise Ecto.NoResultsError, fn ->
        Flows.get_node!(flow.id, -1)
      end
    end
  end

  describe "get_node_by_id!/2" do
    test "returns node without preloads" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      result = Flows.get_node_by_id!(flow.id, node.id)
      assert result.id == node.id
      refute Ecto.assoc_loaded?(result.outgoing_connections)
    end

    test "raises for non-existent node" do
      %{flow: flow} = create_project_and_flow()

      assert_raise Ecto.NoResultsError, fn ->
        Flows.get_node_by_id!(flow.id, -1)
      end
    end
  end

  # ===========================================================================
  # Create operations — by node type
  # ===========================================================================

  describe "create_node/2 — dialogue" do
    test "creates dialogue node with data" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{
          type: "dialogue",
          position_x: 200.0,
          position_y: 300.0,
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "<p>Hello world</p>",
            "stage_directions" => "whispering",
            "menu_text" => "Greet",
            "technical_id" => "dlg_001",
            "responses" => [
              %{"id" => "r1", "text" => "Yes", "condition" => "", "instruction" => ""}
            ]
          }
        })

      assert node.type == "dialogue"
      assert node.position_x == 200.0
      assert node.position_y == 300.0
      assert node.data["text"] == "<p>Hello world</p>"
      assert node.data["stage_directions"] == "whispering"
      assert node.data["menu_text"] == "Greet"
      assert node.data["technical_id"] == "dlg_001"
      assert length(node.data["responses"]) == 1
    end
  end

  describe "create_node/2 — condition" do
    test "creates condition node with expression data" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{
          type: "condition",
          position_x: 300.0,
          position_y: 200.0,
          data: %{
            "expression" => "",
            "cases" => [
              %{"id" => "c1", "value" => "true", "label" => "True"},
              %{"id" => "c2", "value" => "false", "label" => "False"}
            ]
          }
        })

      assert node.type == "condition"
      assert length(node.data["cases"]) == 2
    end
  end

  describe "create_node/2 — instruction" do
    test "creates instruction node with assignments" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{
          type: "instruction",
          position_x: 250.0,
          position_y: 150.0,
          data: %{
            "assignments" => [
              %{
                "sheet" => "mc.hero",
                "variable" => "health",
                "operator" => "set",
                "value" => "100"
              }
            ]
          }
        })

      assert node.type == "instruction"
      assert length(node.data["assignments"]) == 1
    end
  end

  describe "create_node/2 — hub" do
    test "creates hub with explicit hub_id" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "central_plaza", "label" => "Plaza", "color" => "blue"}
        })

      assert hub.type == "hub"
      assert hub.data["hub_id"] == "central_plaza"
      assert hub.data["label"] == "Plaza"
      assert hub.data["color"] == "blue"
    end

    test "auto-generates hub_id when not provided" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"label" => "Auto Hub"}
        })

      assert hub.data["hub_id"] == "hub_1"
    end

    test "auto-generates hub_id when empty string" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "", "label" => "Auto Hub"}
        })

      assert hub.data["hub_id"] == "hub_1"
    end

    test "auto-generates sequential hub_ids" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub1} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{}
        })

      {:ok, hub2} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 400.0,
          position_y: 200.0,
          data: %{}
        })

      assert hub1.data["hub_id"] == "hub_1"
      assert hub2.data["hub_id"] == "hub_2"
    end

    test "rejects duplicate hub_id in same flow" do
      %{flow: flow} = create_project_and_flow()

      {:ok, _} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "unique_id"}
        })

      result =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 400.0,
          position_y: 200.0,
          data: %{"hub_id" => "unique_id"}
        })

      assert result == {:error, :hub_id_not_unique}
    end

    test "allows same hub_id across different flows" do
      %{project: project, flow: flow1} = create_project_and_flow()
      flow2 = flow_fixture(project, %{name: "Flow 2"})

      {:ok, _} =
        Flows.create_node(flow1, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "shared_id"}
        })

      {:ok, hub2} =
        Flows.create_node(flow2, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "shared_id"}
        })

      assert hub2.data["hub_id"] == "shared_id"
    end
  end

  describe "create_node/2 — jump" do
    test "creates jump node with target_hub_id" do
      %{flow: flow} = create_project_and_flow()

      {:ok, _hub} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "target_hub"}
        })

      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"target_hub_id" => "target_hub"}
        })

      assert jump.type == "jump"
      assert jump.data["target_hub_id"] == "target_hub"
    end

    test "creates jump node with empty target" do
      %{flow: flow} = create_project_and_flow()

      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"target_hub_id" => ""}
        })

      assert jump.type == "jump"
      assert jump.data["target_hub_id"] == ""
    end
  end

  describe "create_node/2 — entry" do
    test "rejects duplicate entry node" do
      %{flow: flow} = create_project_and_flow()

      # Flow already has auto-created entry node
      result =
        Flows.create_node(flow, %{
          type: "entry",
          position_x: 200.0,
          position_y: 200.0
        })

      assert result == {:error, :entry_node_exists}
    end
  end

  describe "create_node/2 — exit" do
    test "creates additional exit node" do
      %{flow: flow} = create_project_and_flow()

      {:ok, exit_node} =
        Flows.create_node(flow, %{
          type: "exit",
          position_x: 600.0,
          position_y: 200.0,
          data: %{
            "label" => "Bad Ending",
            "outcome_tags" => ["death", "failure"],
            "outcome_color" => "#ef4444",
            "exit_mode" => "terminal",
            "technical_id" => "exit_bad"
          }
        })

      assert exit_node.type == "exit"
      assert exit_node.data["label"] == "Bad Ending"
      assert exit_node.data["outcome_tags"] == ["death", "failure"]
      assert exit_node.data["outcome_color"] == "#ef4444"
      assert exit_node.data["exit_mode"] == "terminal"
    end

    test "creates exit node with flow_reference mode" do
      %{project: project, flow: flow} = create_project_and_flow()
      target_flow = flow_fixture(project, %{name: "Target Flow"})

      {:ok, exit_node} =
        Flows.create_node(flow, %{
          type: "exit",
          position_x: 600.0,
          position_y: 200.0,
          data: %{
            "label" => "Continue",
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => target_flow.id
          }
        })

      assert exit_node.data["exit_mode"] == "flow_reference"
      assert exit_node.data["referenced_flow_id"] == target_flow.id
    end
  end

  describe "create_node/2 — scene" do
    test "creates scene node with location data" do
      %{flow: flow} = create_project_and_flow()

      {:ok, scene_node} =
        Flows.create_node(flow, %{
          type: "scene",
          position_x: 150.0,
          position_y: 100.0,
          data: %{
            "location" => "INT. TAVERN - NIGHT",
            "slug_line" => "The heroes gather"
          }
        })

      assert scene_node.type == "scene"
      assert scene_node.data["location"] == "INT. TAVERN - NIGHT"
      assert scene_node.data["slug_line"] == "The heroes gather"
    end
  end

  describe "create_node/2 — subflow" do
    test "creates subflow node without reference" do
      %{flow: flow} = create_project_and_flow()

      {:ok, subflow} =
        Flows.create_node(flow, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => nil}
        })

      assert subflow.type == "subflow"
      assert subflow.data["referenced_flow_id"] == nil
    end

    test "creates subflow node with empty string reference" do
      %{flow: flow} = create_project_and_flow()

      {:ok, subflow} =
        Flows.create_node(flow, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => ""}
        })

      assert subflow.type == "subflow"
    end

    test "creates subflow node with valid reference" do
      %{project: project, flow: flow} = create_project_and_flow()
      target_flow = flow_fixture(project, %{name: "Sub Flow"})

      {:ok, subflow} =
        Flows.create_node(flow, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => to_string(target_flow.id)}
        })

      assert subflow.type == "subflow"
      assert subflow.data["referenced_flow_id"] == to_string(target_flow.id)
    end

    test "rejects self-referencing subflow" do
      %{flow: flow} = create_project_and_flow()

      result =
        Flows.create_node(flow, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => to_string(flow.id)}
        })

      assert result == {:error, :self_reference}
    end

    test "rejects invalid (non-numeric) reference" do
      %{flow: flow} = create_project_and_flow()

      result =
        Flows.create_node(flow, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => "not_a_number"}
        })

      assert result == {:error, :invalid_reference}
    end

    test "rejects circular subflow reference" do
      %{project: project, flow: flow_a} = create_project_and_flow()
      flow_b = flow_fixture(project, %{name: "Flow B"})

      # flow_a references flow_b
      {:ok, _} =
        Flows.create_node(flow_a, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => to_string(flow_b.id)}
        })

      # flow_b tries to reference flow_a => circular
      result =
        Flows.create_node(flow_b, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => to_string(flow_a.id)}
        })

      assert result == {:error, :circular_reference}
    end

    test "detects deep circular reference chains" do
      %{project: project, flow: flow_a} = create_project_and_flow()
      flow_b = flow_fixture(project, %{name: "Flow B"})
      flow_c = flow_fixture(project, %{name: "Flow C"})

      # A -> B
      {:ok, _} =
        Flows.create_node(flow_a, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => to_string(flow_b.id)}
        })

      # B -> C
      {:ok, _} =
        Flows.create_node(flow_b, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => to_string(flow_c.id)}
        })

      # C -> A would create A -> B -> C -> A cycle
      result =
        Flows.create_node(flow_c, %{
          type: "subflow",
          position_x: 400.0,
          position_y: 300.0,
          data: %{"referenced_flow_id" => to_string(flow_a.id)}
        })

      assert result == {:error, :circular_reference}
    end
  end

  describe "create_node/2 — validation" do
    test "rejects invalid node type" do
      %{flow: flow} = create_project_and_flow()

      {:error, changeset} =
        Flows.create_node(flow, %{
          type: "nonexistent",
          position_x: 100.0,
          position_y: 100.0
        })

      assert "is invalid" in errors_on(changeset).type
    end

    test "rejects missing type" do
      %{flow: flow} = create_project_and_flow()

      {:error, changeset} =
        Flows.create_node(flow, %{
          position_x: 100.0,
          position_y: 100.0
        })

      assert "can't be blank" in errors_on(changeset).type
    end

    test "accepts atom keys in attrs (stringify_keys)" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{
          type: "dialogue",
          position_x: 100.0,
          position_y: 100.0,
          data: %{text: "Hello"}
        })

      assert node.type == "dialogue"
    end

    test "defaults position to 0.0 when not specified" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} = Flows.create_node(flow, %{type: "dialogue"})

      assert node.position_x == 0.0
      assert node.position_y == 0.0
    end

    test "source defaults to manual" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} = Flows.create_node(flow, %{type: "dialogue"})

      assert node.source == "manual"
    end

    test "accepts screenplay_sync source" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "dialogue", source: "screenplay_sync"})

      assert node.source == "screenplay_sync"
    end
  end

  # ===========================================================================
  # Update operations
  # ===========================================================================

  describe "update_node/2" do
    test "updates node fields" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      {:ok, updated} =
        Flows.update_node(node, %{
          position_x: 999.0,
          position_y: 888.0
        })

      assert updated.position_x == 999.0
      assert updated.position_y == 888.0
    end
  end

  describe "update_node_position/2" do
    test "updates only position fields" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Original"}})

      {:ok, updated} =
        Flows.update_node_position(node, %{position_x: 500.0, position_y: 600.0})

      assert updated.position_x == 500.0
      assert updated.position_y == 600.0
      # data should be unchanged
      assert updated.data["text"] == "Original"
    end

    test "preserves existing position when no attrs given" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue", position_x: 50.0, position_y: 75.0})

      # position_changeset validates_required, but existing values satisfy that
      {:ok, updated} = Flows.update_node_position(node, %{})

      assert updated.position_x == 50.0
      assert updated.position_y == 75.0
    end
  end

  describe "update_node_data/2" do
    test "updates dialogue node data" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Old text"}})

      {:ok, updated, meta} =
        Flows.update_node_data(node, %{"text" => "New text", "speaker_sheet_id" => nil})

      assert updated.data["text"] == "New text"
      assert meta == %{renamed_jumps: 0}
    end

    test "updates condition node expression" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{
          type: "condition",
          data: %{"expression" => ""}
        })

      {:ok, updated, _meta} =
        Flows.update_node_data(node, %{
          "expression" => "mc.hero.health > 50",
          "cases" => [
            %{"id" => "c1", "value" => "true", "label" => "Healthy"},
            %{"id" => "c2", "value" => "false", "label" => "Injured"}
          ]
        })

      assert updated.data["expression"] == "mc.hero.health > 50"
      assert length(updated.data["cases"]) == 2
    end

    test "updates instruction node assignments" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{
          type: "instruction",
          data: %{"assignments" => []}
        })

      {:ok, updated, _meta} =
        Flows.update_node_data(node, %{
          "assignments" => [
            %{
              "sheet" => "mc.hero",
              "variable" => "health",
              "operator" => "add",
              "value" => "10"
            }
          ]
        })

      assert length(updated.data["assignments"]) == 1
    end

    test "updates hub node data with hub_id uniqueness check" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "hub_alpha", "label" => "Alpha", "color" => "blue"}
        })

      {:ok, updated, meta} =
        Flows.update_node_data(hub, %{
          "hub_id" => "hub_alpha",
          "label" => "Updated Alpha",
          "color" => "red"
        })

      assert updated.data["label"] == "Updated Alpha"
      assert updated.data["color"] == "red"
      assert meta == %{renamed_jumps: 0}
    end

    test "hub rename cascades to referencing jump nodes" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "old_hub", "label" => "Hub"}
        })

      {:ok, _jump} =
        Flows.create_node(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "old_hub"}
        })

      {:ok, _updated_hub, meta} =
        Flows.update_node_data(hub, %{
          "hub_id" => "new_hub",
          "label" => "Hub"
        })

      assert meta.renamed_jumps == 1

      # Verify jump was updated
      jumps =
        Flows.list_nodes(flow.id)
        |> Enum.filter(&(&1.type == "jump"))

      jump = hd(jumps)
      assert jump.data["target_hub_id"] == "new_hub"
    end

    test "hub update rejects empty hub_id" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "my_hub", "label" => "Hub"}
        })

      result = Flows.update_node_data(hub, %{"hub_id" => "", "label" => "Hub"})
      assert result == {:error, :hub_id_required}
    end

    test "hub update rejects nil hub_id" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "my_hub", "label" => "Hub"}
        })

      result = Flows.update_node_data(hub, %{"hub_id" => nil, "label" => "Hub"})
      assert result == {:error, :hub_id_required}
    end

    test "hub update rejects duplicate hub_id" do
      %{flow: flow} = create_project_and_flow()

      {:ok, _hub1} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "taken"}
        })

      {:ok, hub2} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "available"}
        })

      result = Flows.update_node_data(hub2, %{"hub_id" => "taken"})
      assert result == {:error, :hub_id_not_unique}
    end

    test "updates scene node data" do
      %{flow: flow} = create_project_and_flow()

      {:ok, scene} =
        Flows.create_node(flow, %{
          type: "scene",
          data: %{"location" => "INT. OFFICE - DAY"}
        })

      {:ok, updated, _meta} =
        Flows.update_node_data(scene, %{
          "location" => "EXT. PARK - NIGHT",
          "slug_line" => "A quiet evening"
        })

      assert updated.data["location"] == "EXT. PARK - NIGHT"
      assert updated.data["slug_line"] == "A quiet evening"
    end
  end

  describe "batch_update_positions/2" do
    test "updates multiple nodes in one transaction" do
      %{flow: flow} = create_project_and_flow()
      node1 = node_fixture(flow, %{position_x: 0.0, position_y: 0.0})
      node2 = node_fixture(flow, %{position_x: 0.0, position_y: 0.0})

      positions = [
        %{id: node1.id, position_x: 100.0, position_y: 200.0},
        %{id: node2.id, position_x: 300.0, position_y: 400.0}
      ]

      assert {:ok, 2} = Flows.batch_update_positions(flow.id, positions)

      updated1 = Flows.get_node!(flow.id, node1.id)
      assert updated1.position_x == 100.0
      assert updated1.position_y == 200.0

      updated2 = Flows.get_node!(flow.id, node2.id)
      assert updated2.position_x == 300.0
      assert updated2.position_y == 400.0
    end

    test "handles empty list" do
      %{flow: flow} = create_project_and_flow()
      assert {:ok, 0} = Flows.batch_update_positions(flow.id, [])
    end

    test "ignores nodes from different flow" do
      %{project: project, flow: flow} = create_project_and_flow()
      other_flow = flow_fixture(project, %{name: "Other"})
      other_node = node_fixture(other_flow, %{position_x: 10.0, position_y: 20.0})

      positions = [%{id: other_node.id, position_x: 999.0, position_y: 999.0}]
      Flows.batch_update_positions(flow.id, positions)

      unchanged = Flows.get_node!(other_flow.id, other_node.id)
      assert unchanged.position_x == 10.0
      assert unchanged.position_y == 20.0
    end
  end

  describe "change_node/2" do
    test "returns a changeset for tracking changes" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      changeset = Flows.change_node(node, %{position_x: 999.0})

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :position_x) == 999.0
    end

    test "returns changeset with no changes when attrs empty" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      changeset = Flows.change_node(node)

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes == %{}
    end
  end

  # ===========================================================================
  # Delete operations
  # ===========================================================================

  describe "delete_node/1" do
    test "soft-deletes a dialogue node" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      {:ok, deleted, meta} = Flows.delete_node(node)

      assert deleted.id == node.id
      assert deleted.deleted_at != nil
      assert meta == %{orphaned_jumps: 0}
      assert Flows.get_node(flow.id, node.id) == nil
    end

    test "soft-deletes an instruction node" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "instruction", data: %{"assignments" => []}})

      {:ok, deleted, _meta} = Flows.delete_node(node)
      assert deleted.deleted_at != nil
    end

    test "soft-deletes a condition node" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "condition", data: %{"expression" => ""}})

      {:ok, deleted, _meta} = Flows.delete_node(node)
      assert deleted.deleted_at != nil
    end

    test "soft-deletes a scene node" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "scene", data: %{"location" => "INT. OFFICE"}})

      {:ok, deleted, _meta} = Flows.delete_node(node)
      assert deleted.deleted_at != nil
    end

    test "soft-deletes a jump node" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "jump", data: %{"target_hub_id" => ""}})

      {:ok, deleted, _meta} = Flows.delete_node(node)
      assert deleted.deleted_at != nil
    end

    test "soft-deletes a subflow node" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "subflow", data: %{"referenced_flow_id" => nil}})

      {:ok, deleted, _meta} = Flows.delete_node(node)
      assert deleted.deleted_at != nil
    end

    test "cannot delete entry node" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)

      result = Flows.delete_node(entry)
      assert result == {:error, :cannot_delete_entry_node}
    end

    test "cannot delete the last exit node" do
      %{flow: flow} = create_project_and_flow()
      exit_node = get_exit_node(flow)

      result = Flows.delete_node(exit_node)
      assert result == {:error, :cannot_delete_last_exit}
    end

    test "can delete exit when multiple exits exist" do
      %{flow: flow} = create_project_and_flow()

      {:ok, extra_exit} =
        Flows.create_node(flow, %{
          type: "exit",
          data: %{"label" => "Extra", "exit_mode" => "terminal"}
        })

      {:ok, deleted, _meta} = Flows.delete_node(extra_exit)
      assert deleted.id == extra_exit.id
    end

    test "deleting hub clears referencing jump target_hub_ids" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "deletable_hub", "label" => "Hub"}
        })

      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "deletable_hub"}
        })

      {:ok, _deleted, meta} = Flows.delete_node(hub)

      assert meta.orphaned_jumps == 1

      # Verify jump target was cleared
      updated_jump = Flows.get_node!(flow.id, jump.id)
      assert updated_jump.data["target_hub_id"] == ""
    end

    test "deleting hub with multiple referencing jumps clears all" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "multi_hub", "label" => "Hub"}
        })

      {:ok, _j1} =
        Flows.create_node(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "multi_hub"}
        })

      {:ok, _j2} =
        Flows.create_node(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "multi_hub"}
        })

      {:ok, _deleted, meta} = Flows.delete_node(hub)
      assert meta.orphaned_jumps == 2
    end

    test "deleting non-hub node reports zero orphaned jumps" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      {:ok, _deleted, meta} = Flows.delete_node(node)
      assert meta.orphaned_jumps == 0
    end
  end

  describe "restore_node/2" do
    test "restores a soft-deleted node" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Restored!"}})

      {:ok, _deleted, _meta} = Flows.delete_node(node)
      assert Flows.get_node(flow.id, node.id) == nil

      {:ok, restored} = Flows.restore_node(flow.id, node.id)
      assert restored.deleted_at == nil
      assert restored.data["text"] == "Restored!"
    end

    test "returns :already_active for non-deleted node" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      assert {:ok, :already_active} = Flows.restore_node(flow.id, node.id)
    end

    test "returns :not_found for wrong flow_id" do
      %{project: project, flow: flow1} = create_project_and_flow()
      flow2 = flow_fixture(project, %{name: "Other"})
      node = node_fixture(flow1, %{type: "dialogue"})

      {:ok, _deleted, _meta} = Flows.delete_node(node)

      assert {:error, :not_found} = Flows.restore_node(flow2.id, node.id)
    end

    test "returns :not_found for nonexistent node" do
      %{flow: flow} = create_project_and_flow()

      assert {:error, :not_found} = Flows.restore_node(flow.id, -1)
    end
  end

  # ===========================================================================
  # Hub query helpers
  # ===========================================================================

  describe "hub_id_exists?/3" do
    test "returns true when hub_id exists" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "check_me"}
        })

      assert Flows.NodeCrud.hub_id_exists?(flow.id, "check_me", nil) == true
      # Excluding the hub itself should return false
      assert Flows.NodeCrud.hub_id_exists?(flow.id, "check_me", hub.id) == false
    end

    test "returns false when hub_id does not exist" do
      %{flow: flow} = create_project_and_flow()

      assert Flows.NodeCrud.hub_id_exists?(flow.id, "nonexistent", nil) == false
    end
  end

  describe "list_hubs/1" do
    test "returns all hubs in a flow" do
      %{flow: flow} = create_project_and_flow()

      {:ok, _} =
        Flows.create_node(flow, %{type: "hub", data: %{"hub_id" => "h1", "label" => "One"}})

      {:ok, _} =
        Flows.create_node(flow, %{type: "hub", data: %{"hub_id" => "h2", "label" => "Two"}})

      hubs = Flows.list_hubs(flow.id)

      assert length(hubs) == 2
      hub_ids = Enum.map(hubs, & &1.hub_id) |> Enum.sort()
      assert hub_ids == ["h1", "h2"]
    end

    test "returns empty list when no hubs" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.list_hubs(flow.id) == []
    end
  end

  describe "get_hub_by_hub_id/2" do
    test "finds hub by hub_id string" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "findable", "label" => "Found"}
        })

      found = Flows.get_hub_by_hub_id(flow.id, "findable")
      assert found.id == hub.id
    end

    test "returns nil for nonexistent hub_id" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.get_hub_by_hub_id(flow.id, "missing") == nil
    end
  end

  describe "list_referencing_jumps/2" do
    test "returns jumps referencing a hub_id" do
      %{flow: flow} = create_project_and_flow()

      {:ok, _hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "ref_hub"}
        })

      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          position_x: 100.0,
          position_y: 200.0,
          data: %{"target_hub_id" => "ref_hub"}
        })

      refs = Flows.list_referencing_jumps(flow.id, "ref_hub")

      assert length(refs) == 1
      assert hd(refs).id == jump.id
    end

    test "returns empty list for empty hub_id" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.list_referencing_jumps(flow.id, "") == []
    end

    test "returns empty list for nil hub_id" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.list_referencing_jumps(flow.id, nil) == []
    end
  end

  # ===========================================================================
  # Count and listing helpers
  # ===========================================================================

  describe "count_nodes_by_type/1" do
    test "returns count grouped by type" do
      %{flow: flow} = create_project_and_flow()

      node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "condition"})

      counts = Flows.count_nodes_by_type(flow.id)

      assert counts["entry"] == 1
      assert counts["exit"] == 1
      assert counts["dialogue"] == 2
      assert counts["condition"] == 1
    end

    test "returns empty map for flow with no nodes (impossible due to auto-create)" do
      %{flow: flow} = create_project_and_flow()

      counts = Flows.count_nodes_by_type(flow.id)
      # Auto-created entry + exit
      assert counts["entry"] == 1
      assert counts["exit"] == 1
    end
  end

  describe "list_exit_nodes_for_flow/1" do
    test "returns exit nodes with data fields" do
      %{flow: flow} = create_project_and_flow()

      {:ok, _} =
        Flows.create_node(flow, %{
          type: "exit",
          data: %{
            "label" => "Victory",
            "outcome_tags" => ["win"],
            "outcome_color" => "#22c55e",
            "exit_mode" => "terminal"
          }
        })

      exits = Flows.list_exit_nodes_for_flow(flow.id)

      # Auto-created exit + manual = 2
      assert length(exits) == 2

      victory = Enum.find(exits, &(&1.label == "Victory"))
      assert victory.outcome_tags == ["win"]
      assert victory.outcome_color == "#22c55e"
      assert victory.exit_mode == "terminal"
    end
  end

  describe "list_outcome_tags_for_project/1" do
    test "returns unique sorted tags from exit nodes" do
      %{project: project, flow: flow} = create_project_and_flow()

      {:ok, _} =
        Flows.create_node(flow, %{
          type: "exit",
          data: %{"label" => "End 1", "outcome_tags" => ["death", "failure"]}
        })

      {:ok, _} =
        Flows.create_node(flow, %{
          type: "exit",
          data: %{"label" => "End 2", "outcome_tags" => ["success", "death"]}
        })

      tags = Flows.list_outcome_tags_for_project(project.id)

      assert tags == ["death", "failure", "success"]
    end

    test "returns empty list when no outcome tags" do
      %{project: project} = create_project_and_flow()

      # Auto-created exit has empty outcome_tags
      assert Flows.list_outcome_tags_for_project(project.id) == []
    end
  end

  # ===========================================================================
  # Subflow / exit data resolution
  # ===========================================================================

  describe "batch_resolve_subflow_data/1" do
    test "returns empty map when no subflow nodes" do
      %{flow: flow} = create_project_and_flow()
      nodes = Flows.list_nodes(flow.id)

      result = Flows.NodeCrud.batch_resolve_subflow_data(nodes)
      assert result == %{}
    end

    test "resolves subflow references with flow names and exit labels" do
      %{project: project, flow: flow} = create_project_and_flow()
      target_flow = flow_fixture(project, %{name: "Target Sub"})

      {:ok, subflow_node} =
        Flows.create_node(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => to_string(target_flow.id)}
        })

      nodes = [subflow_node]
      result = Flows.NodeCrud.batch_resolve_subflow_data(nodes)

      assert Map.has_key?(result, target_flow.id)
      assert result[target_flow.id].flow.name == "Target Sub"
      # Target flow has auto-created exit node
      assert length(result[target_flow.id].exit_labels) == 1
    end
  end

  describe "resolve_subflow_data/2" do
    test "enriches data with flow name when reference is valid" do
      %{project: project, flow: flow} = create_project_and_flow()
      target_flow = flow_fixture(project, %{name: "Enriched Flow"})

      {:ok, subflow} =
        Flows.create_node(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => to_string(target_flow.id)}
        })

      cache = Flows.NodeCrud.batch_resolve_subflow_data([subflow])
      resolved = Flows.NodeCrud.resolve_subflow_data(subflow.data, cache)

      assert resolved["referenced_flow_name"] == "Enriched Flow"
      assert resolved["stale_reference"] == false
    end

    test "returns data unchanged when referenced_flow_id is nil" do
      data = %{"referenced_flow_id" => nil}
      resolved = Flows.NodeCrud.resolve_subflow_data(data, %{})
      assert resolved == data
    end

    test "returns data unchanged when referenced_flow_id is empty string" do
      data = %{"referenced_flow_id" => ""}
      resolved = Flows.NodeCrud.resolve_subflow_data(data, %{})
      assert resolved == data
    end

    test "marks stale when referenced flow does not exist in cache (fallback query)" do
      data = %{"referenced_flow_id" => "999999"}
      resolved = Flows.NodeCrud.resolve_subflow_data(data, %{})

      assert resolved["stale_reference"] == true
      assert resolved["referenced_flow_name"] == nil
      assert resolved["exit_labels"] == []
    end
  end

  describe "resolve_exit_data/1" do
    test "returns data unchanged for terminal exit mode" do
      data = %{"exit_mode" => "terminal", "label" => "End"}
      result = Flows.NodeCrud.resolve_exit_data(data)
      assert result == data
    end

    test "returns data unchanged for exit without exit_mode key" do
      data = %{"label" => "Basic exit"}
      result = Flows.NodeCrud.resolve_exit_data(data)
      assert result == data
    end

    test "enriches flow_reference exit with flow name" do
      %{project: project} = create_project_and_flow()
      target_flow = flow_fixture(project, %{name: "Referenced Flow"})

      data = %{
        "exit_mode" => "flow_reference",
        "referenced_flow_id" => to_string(target_flow.id)
      }

      result = Flows.NodeCrud.resolve_exit_data(data)

      assert result["stale_reference"] == false
      assert result["referenced_flow_name"] == "Referenced Flow"
    end

    test "returns data unchanged when referenced flow does not exist" do
      data = %{
        "exit_mode" => "flow_reference",
        "referenced_flow_id" => "999999"
      }

      # When Repo.get returns nil, the with clause falls through to
      # the nil -> data branch, returning data unchanged (not stale-marked)
      result = Flows.NodeCrud.resolve_exit_data(data)
      assert result == data
    end

    test "marks stale when referenced flow is soft-deleted" do
      %{project: project} = create_project_and_flow()
      target_flow = flow_fixture(project, %{name: "Soon Deleted"})

      Flows.delete_flow(target_flow)

      data = %{
        "exit_mode" => "flow_reference",
        "referenced_flow_id" => to_string(target_flow.id)
      }

      result = Flows.NodeCrud.resolve_exit_data(data)

      assert result["stale_reference"] == true
      assert result["referenced_flow_name"] == nil
    end

    test "returns unchanged when flow_reference has nil referenced_flow_id" do
      data = %{
        "exit_mode" => "flow_reference",
        "referenced_flow_id" => nil
      }

      result = Flows.NodeCrud.resolve_exit_data(data)
      assert result == data
    end
  end

  # ===========================================================================
  # Cross-reference queries
  # ===========================================================================

  describe "list_subflow_nodes_referencing/2" do
    test "finds subflow nodes referencing a given flow" do
      %{project: project, flow: flow_a} = create_project_and_flow()
      flow_b = flow_fixture(project, %{name: "Flow B"})

      {:ok, subflow} =
        Flows.create_node(flow_b, %{
          type: "subflow",
          data: %{"referenced_flow_id" => to_string(flow_a.id)}
        })

      refs = Flows.list_subflow_nodes_referencing(flow_a.id, project.id)

      assert length(refs) == 1
      assert hd(refs).id == subflow.id
      assert hd(refs).flow_id == flow_b.id
    end

    test "returns empty list when no references" do
      %{project: project, flow: flow} = create_project_and_flow()

      assert Flows.list_subflow_nodes_referencing(flow.id, project.id) == []
    end
  end

  describe "list_nodes_referencing_flow/2" do
    test "finds subflow and exit flow_reference nodes" do
      %{project: project, flow: target_flow} = create_project_and_flow()
      referencing_flow = flow_fixture(project, %{name: "Referencing Flow"})

      # Subflow reference
      {:ok, _subflow} =
        Flows.create_node(referencing_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => to_string(target_flow.id)}
        })

      # Exit flow_reference
      {:ok, _exit} =
        Flows.create_node(referencing_flow, %{
          type: "exit",
          data: %{
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => to_string(target_flow.id)
          }
        })

      refs = Flows.list_nodes_referencing_flow(target_flow.id, project.id)

      assert length(refs) == 2
      types = Enum.map(refs, & &1.node_type) |> Enum.sort()
      assert types == ["exit", "subflow"]
    end
  end

  # ===========================================================================
  # Circular reference detection
  # ===========================================================================

  describe "has_circular_reference?/2" do
    test "returns false for non-circular reference" do
      %{project: project, flow: flow_a} = create_project_and_flow()
      flow_b = flow_fixture(project, %{name: "Flow B"})

      refute Flows.has_circular_reference?(flow_a.id, flow_b.id)
    end

    test "returns true for direct circular reference" do
      %{project: project, flow: flow_a} = create_project_and_flow()
      flow_b = flow_fixture(project, %{name: "Flow B"})

      # B references A
      {:ok, _} =
        Flows.create_node(flow_b, %{
          type: "subflow",
          data: %{"referenced_flow_id" => to_string(flow_a.id)}
        })

      # A -> B would be circular since B -> A exists
      assert Flows.has_circular_reference?(flow_a.id, flow_b.id)
    end
  end

  # ===========================================================================
  # safe_to_integer
  # ===========================================================================

  describe "safe_to_integer/1" do
    test "returns integer for integer input" do
      assert Flows.safe_to_integer(42) == 42
    end

    test "parses string integer" do
      assert Flows.safe_to_integer("123") == 123
    end

    test "returns nil for non-numeric string" do
      assert Flows.safe_to_integer("abc") == nil
    end

    test "returns nil for partial numeric string" do
      assert Flows.safe_to_integer("42abc") == nil
    end

    test "returns nil for nil" do
      assert Flows.safe_to_integer(nil) == nil
    end

    test "returns nil for other types" do
      assert Flows.safe_to_integer(3.14) == nil
    end
  end

  # ===========================================================================
  # Connection-aware deletion
  # ===========================================================================

  describe "delete_node/1 — connection cleanup" do
    test "connections involving deleted node are excluded from list_connections" do
      %{flow: flow} = create_project_and_flow()
      node1 = node_fixture(flow, %{type: "dialogue"})
      node2 = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, node1, node2)

      assert length(Flows.list_connections(flow.id)) == 1

      {:ok, _deleted, _meta} = Flows.delete_node(node1)

      # list_connections joins on active source/target nodes,
      # so connections with a soft-deleted endpoint are excluded
      connections = Flows.list_connections(flow.id)
      assert length(connections) == 0
    end

    test "node with incoming and outgoing connections" do
      %{flow: flow} = create_project_and_flow()
      node_a = node_fixture(flow, %{type: "dialogue"})
      node_b = node_fixture(flow, %{type: "dialogue"})
      node_c = node_fixture(flow, %{type: "dialogue"})

      _conn1 = connection_fixture(flow, node_a, node_b)
      _conn2 = connection_fixture(flow, node_b, node_c)

      assert length(Flows.list_connections(flow.id)) == 2

      {:ok, _deleted, _meta} = Flows.delete_node(node_b)

      assert Flows.get_node(flow.id, node_b.id) == nil
      # Other nodes remain
      assert Flows.get_node(flow.id, node_a.id) != nil
      assert Flows.get_node(flow.id, node_c.id) != nil

      # Both connections are excluded since node_b is soft-deleted
      assert length(Flows.list_connections(flow.id)) == 0
    end

    test "connections between surviving nodes are preserved" do
      %{flow: flow} = create_project_and_flow()
      node_a = node_fixture(flow, %{type: "dialogue"})
      node_b = node_fixture(flow, %{type: "dialogue"})
      node_c = node_fixture(flow, %{type: "dialogue"})

      _conn1 = connection_fixture(flow, node_a, node_b)
      _conn2 = connection_fixture(flow, node_a, node_c)

      # Delete node_b; connection A->C should remain
      {:ok, _deleted, _meta} = Flows.delete_node(node_b)

      connections = Flows.list_connections(flow.id)
      assert length(connections) == 1
      assert hd(connections).target_node_id == node_c.id
    end
  end

  # ===========================================================================
  # All 9 node types - create + roundtrip verify
  # ===========================================================================

  describe "all 9 node types — create roundtrip" do
    test "entry — auto-created by flow" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      assert entry.type == "entry"
    end

    test "exit — auto-created by flow" do
      %{flow: flow} = create_project_and_flow()
      exit_node = get_exit_node(flow)
      assert exit_node.type == "exit"
    end

    test "dialogue" do
      %{flow: flow} = create_project_and_flow()
      {:ok, node} = Flows.create_node(flow, %{type: "dialogue", data: %{"text" => "Hi"}})
      fetched = Flows.get_node!(flow.id, node.id)
      assert fetched.type == "dialogue"
      assert fetched.data["text"] == "Hi"
    end

    test "condition" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "condition", data: %{"expression" => "x > 5"}})

      fetched = Flows.get_node!(flow.id, node.id)
      assert fetched.type == "condition"
      assert fetched.data["expression"] == "x > 5"
    end

    test "instruction" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "instruction", data: %{"assignments" => []}})

      fetched = Flows.get_node!(flow.id, node.id)
      assert fetched.type == "instruction"
    end

    test "hub" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "hub", data: %{"hub_id" => "rt_hub", "label" => "RT"}})

      fetched = Flows.get_node!(flow.id, node.id)
      assert fetched.type == "hub"
      assert fetched.data["hub_id"] == "rt_hub"
    end

    test "jump" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "jump", data: %{"target_hub_id" => ""}})

      fetched = Flows.get_node!(flow.id, node.id)
      assert fetched.type == "jump"
    end

    test "scene" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "scene", data: %{"location" => "EXT. BEACH"}})

      fetched = Flows.get_node!(flow.id, node.id)
      assert fetched.type == "scene"
      assert fetched.data["location"] == "EXT. BEACH"
    end

    test "subflow" do
      %{flow: flow} = create_project_and_flow()

      {:ok, node} =
        Flows.create_node(flow, %{type: "subflow", data: %{"referenced_flow_id" => nil}})

      fetched = Flows.get_node!(flow.id, node.id)
      assert fetched.type == "subflow"
    end
  end

  # ===========================================================================
  # Module 3A: NodeDelete — additional coverage
  # ===========================================================================

  describe "delete_node/1 — hub with nil/empty hub_id" do
    test "deleting hub with nil hub_id does not crash" do
      %{flow: flow} = create_project_and_flow()

      # Create a hub node with a valid hub_id
      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "temp_hub", "label" => "Temp"}
        })

      # Bypass validation to set hub_id to nil in data using low-level changeset
      # This exercises the clear_orphaned_jumps(_flow_id, _hub_id) fallback on L88
      alias Storyarn.Flows.FlowNode

      {:ok, updated_hub} =
        hub
        |> FlowNode.data_changeset(%{data: %{"hub_id" => nil, "label" => "Nil Hub"}})
        |> Storyarn.Repo.update()

      {:ok, deleted, meta} = Flows.delete_node(updated_hub)
      assert deleted.deleted_at != nil
      # With nil hub_id, the fallback clause returns 0
      assert meta.orphaned_jumps == 0
    end
  end

  # ===========================================================================
  # Module 3E: FlowNode schema — additional coverage
  # ===========================================================================

  describe "FlowNode schema" do
    alias Storyarn.Flows.FlowNode

    test "node_types/0 returns all valid node types" do
      types = FlowNode.node_types()
      assert is_list(types)
      assert "dialogue" in types
      assert "hub" in types
      assert "condition" in types
      assert "instruction" in types
      assert "jump" in types
      assert "entry" in types
      assert "exit" in types
      assert "subflow" in types
      assert "scene" in types
      assert length(types) == 9
    end

    test "create_changeset rejects invalid type" do
      changeset =
        FlowNode.create_changeset(%FlowNode{}, %{type: "invalid_type"})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).type
    end

    test "create_changeset rejects invalid source" do
      changeset =
        FlowNode.create_changeset(%FlowNode{}, %{type: "dialogue", source: "invalid_source"})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).source
    end

    test "position_changeset requires both position fields on a bare struct" do
      # Use a bare struct where position fields default to 0.0
      # The changeset casts and validates presence
      bare_node = %FlowNode{position_x: nil, position_y: nil}

      changeset = FlowNode.position_changeset(bare_node, %{position_x: 100.0})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).position_y

      changeset2 = FlowNode.position_changeset(bare_node, %{position_y: 200.0})
      refute changeset2.valid?
      assert "can't be blank" in errors_on(changeset2).position_x
    end

    test "position_changeset accepts valid positions" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      changeset = FlowNode.position_changeset(node, %{position_x: 500.0, position_y: 600.0})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :position_x) == 500.0
      assert Ecto.Changeset.get_change(changeset, :position_y) == 600.0
    end

    test "data_changeset accepts map data" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      changeset =
        FlowNode.data_changeset(node, %{data: %{"text" => "updated"}})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :data) == %{"text" => "updated"}
    end
  end

  # ===========================================================================
  # Module 3F: Flow schema — additional coverage
  # ===========================================================================

  describe "Flow schema" do
    alias Storyarn.Flows.Flow

    test "create_changeset rejects name exceeding 200 characters" do
      long_name = String.duplicate("a", 201)
      changeset = Flow.create_changeset(%Flow{}, %{name: long_name})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert Enum.any?(errors.name, &String.contains?(&1, "200"))
    end

    test "create_changeset rejects empty name" do
      changeset = Flow.create_changeset(%Flow{}, %{name: ""})

      refute changeset.valid?
    end

    test "scene_changeset accepts scene_id" do
      %{project: project} = create_project_and_flow()
      flow = flow_fixture(project, %{name: "Scene Flow"})

      changeset = Flow.scene_changeset(flow, %{scene_id: nil})
      assert changeset.valid?
    end

    test "shortcut uniqueness constraint raises on duplicate" do
      %{project: project} = create_project_and_flow()

      {:ok, _flow1} =
        Flows.create_flow(project, %{name: "Flow A", shortcut: "unique-shortcut"})

      {:error, changeset} =
        Flows.create_flow(project, %{name: "Flow B", shortcut: "unique-shortcut"})

      assert "is already taken in this project" in errors_on(changeset).shortcut
    end
  end
end
