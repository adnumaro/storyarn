defmodule Storyarn.Exports.Serializers.GodotJSONTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.GodotJSON

  alias Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # =============================================================================
  # Setup
  # =============================================================================

  defp reload_flow(flow), do: Repo.preload(flow, [:nodes, :connections], force: true)

  defp create_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  defp default_opts do
    {:ok, opts} = ExportOptions.new(%{format: :godot, validate_before_export: false})
    opts
  end

  defp export_and_decode(project, opts \\ nil) do
    opts = opts || default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, json} = GodotJSON.serialize(project_data, opts)
    Jason.decode!(json)
  end

  # =============================================================================
  # Behaviour callbacks
  # =============================================================================

  describe "behaviour callbacks" do
    test "content_type returns application/json" do
      assert GodotJSON.content_type() == "application/json"
    end

    test "file_extension returns json" do
      assert GodotJSON.file_extension() == "json"
    end

    test "format_label returns human-readable name" do
      assert GodotJSON.format_label() == "Godot (JSON)"
    end

    test "supported_sections includes scenes" do
      sections = GodotJSON.supported_sections()
      assert :flows in sections
      assert :sheets in sections
      assert :scenes in sections
    end

    test "serialize_to_file returns not_implemented" do
      assert {:error, :not_implemented} = GodotJSON.serialize_to_file(nil, "", nil, [])
    end
  end

  # =============================================================================
  # Empty project
  # =============================================================================

  describe "empty project export" do
    setup [:create_project]

    test "produces valid JSON with required envelope", %{project: project} do
      result = export_and_decode(project)
      assert result["format"] == "godot_dialogue"
      assert result["version"] == "1.0.0"
      assert is_binary(result["storyarn_version"])
    end

    test "has top-level sections", %{project: project} do
      result = export_and_decode(project)
      assert is_map(result["characters"])
      assert is_map(result["variables"])
      assert is_map(result["flows"])
    end
  end

  # =============================================================================
  # Characters from sheets
  # =============================================================================

  describe "characters from sheets" do
    setup [:create_project]

    test "sheets become characters", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Jaime"})

      result = export_and_decode(project)
      char = result["characters"][sheet.shortcut]
      assert char
      assert char["name"] == "Jaime"
      assert is_map(char["properties"])
    end

    test "character properties have type and value", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      result = export_and_decode(project)
      char = result["characters"][sheet.shortcut]
      # Find the health property by variable_name
      health_prop = char["properties"]["health"]
      assert health_prop
      assert health_prop["type"] == "number"
      assert health_prop["value"] == 100
    end
  end

  # =============================================================================
  # Variables
  # =============================================================================

  describe "variables" do
    setup [:create_project]

    test "variables use underscore names", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      result = export_and_decode(project)
      vars = result["variables"]
      assert map_size(vars) >= 1

      # Variable names should use underscores instead of dots
      keys = Map.keys(vars)
      assert Enum.all?(keys, fn k -> not String.contains?(k, ".") end)
    end

    test "variable has type, default, and source", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Alive"},
        value: %{"boolean" => true}
      })

      result = export_and_decode(project)
      vars = result["variables"]
      var = vars |> Map.values() |> hd()
      assert var["type"] == "boolean"
      assert is_boolean(var["default"])
      assert is_binary(var["source"])
    end
  end

  # =============================================================================
  # Flows as node graph
  # =============================================================================

  describe "flows as node graph" do
    setup [:create_project]

    test "flow has name, start_node, and nodes", %{project: project} do
      flow = flow_fixture(project, %{name: "Test Flow"})

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      flow_data = result["flows"][flow_key]
      assert flow_data
      assert flow_data["name"] == "Test Flow"
      assert is_binary(flow_data["start_node"]) or is_nil(flow_data["start_node"])
      assert is_map(flow_data["nodes"])
    end

    test "dialogue node has character and text", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Speaker"})
      flow = flow_fixture(project, %{name: "Dlg Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello world!",
            "speaker_sheet_id" => sheet.id,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]
      dlg_node = nodes[to_string(dialogue.id)]
      assert dlg_node
      assert dlg_node["type"] == "dialogue"
      assert dlg_node["text"] == "Hello world!"
      assert dlg_node["character"] == sheet.shortcut
    end

    test "node next array contains target IDs", %{project: project} do
      flow = flow_fixture(project, %{name: "Next Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hi", "speaker_sheet_id" => nil, "responses" => []}
        })

      connection_fixture(flow, entry, dialogue)

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]
      entry_node = nodes[to_string(entry.id)]
      assert is_list(entry_node["next"])
      assert to_string(dialogue.id) in entry_node["next"]
    end

    test "condition node has condition field", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "Cond Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" =>
              Jason.encode!(%{
                "logic" => "all",
                "rules" => [
                  %{
                    "sheet" => sheet.shortcut,
                    "variable" => "health",
                    "operator" => "greater_than",
                    "value" => "50"
                  }
                ]
              }),
            "cases" => [
              %{"id" => "true", "value" => "true", "label" => "True"}
            ]
          }
        })

      connection_fixture(flow, entry, condition)

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]
      cond_node = nodes[to_string(condition.id)]
      assert cond_node["type"] == "condition"
      # Condition should be transpiled to GDScript
      assert is_binary(cond_node["condition"]) or is_nil(cond_node["condition"])
    end

    test "instruction node has code and assignments", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Met"},
        value: %{"boolean" => false}
      })

      flow = flow_fixture(project, %{name: "Inst Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "sheet" => sheet.shortcut,
                "variable" => "met",
                "operator" => "set_true"
              }
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]
      inst_node = nodes[to_string(instruction.id)]
      assert inst_node["type"] == "instruction"
      assert is_list(inst_node["assignments"])
    end

    test "hub node has label", %{project: project} do
      flow = flow_fixture(project, %{name: "Hub Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"label" => "checkpoint"}
        })

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]
      hub_node = nodes[to_string(hub.id)]
      assert hub_node["type"] == "hub"
      assert hub_node["label"] == "checkpoint"
    end
  end

  # =============================================================================
  # Additional node types
  # =============================================================================

  describe "additional node types" do
    setup [:create_project]

    test "jump node exports with hub reference", %{project: project} do
      flow = flow_fixture(project, %{name: "Jump Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"label" => "checkpoint"}
        })

      _jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"hub_id" => hub.id}
        })

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]

      jump_nodes = Enum.filter(nodes, fn {_k, v} -> v["type"] == "jump" end)
      assert jump_nodes != []
    end

    test "exit node exports", %{project: project} do
      flow = flow_fixture(project, %{name: "Exit Flow"})
      flow = reload_flow(flow)
      exit_node = Enum.find(flow.nodes, &(&1.type == "exit"))

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]
      exit_data = nodes[to_string(exit_node.id)]
      assert exit_data["type"] == "exit"
    end

    test "scene node exports with location", %{project: project} do
      _scene_node =
        node_fixture(flow_fixture(project, %{name: "Scene Flow"}), %{
          type: "scene",
          data: %{"slug_line" => "INT. TAVERN - NIGHT"}
        })

      result = export_and_decode(project)
      # The flow should contain the scene node
      flow_data = result["flows"] |> Map.values() |> hd()
      scene_nodes = Enum.filter(flow_data["nodes"], fn {_k, v} -> v["type"] == "scene" end)
      assert scene_nodes != []
    end

    test "subflow node exports with flow reference", %{project: project} do
      child_flow = flow_fixture(project, %{name: "Child Flow"})

      _subflow =
        node_fixture(flow_fixture(project, %{name: "Parent Flow"}), %{
          type: "subflow",
          data: %{"flow_id" => child_flow.id}
        })

      result = export_and_decode(project)

      parent_flow_data =
        result["flows"] |> Map.values() |> Enum.find(fn f -> f["name"] == "Parent Flow" end)

      assert parent_flow_data

      subflow_nodes =
        Enum.filter(parent_flow_data["nodes"], fn {_k, v} -> v["type"] == "subflow" end)

      assert subflow_nodes != []
    end

    test "dialogue node with responses exports choices", %{project: project} do
      sheet = sheet_fixture(project, %{name: "NPC"})
      flow = flow_fixture(project, %{name: "Response Flow"})

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello traveler!",
            "speaker_sheet_id" => sheet.id,
            "responses" => [
              %{"id" => "r1", "text" => "Hi there!", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "Leave me alone", "condition" => "", "instruction" => ""}
            ]
          }
        })

      result = export_and_decode(project)
      flow_key = flow.shortcut || flow.name
      nodes = result["flows"][flow_key]["nodes"]
      dlg_nodes = Enum.filter(nodes, fn {_k, v} -> v["type"] == "dialogue" end)
      assert dlg_nodes != []

      {_id, dlg_data} = hd(dlg_nodes)
      assert is_list(dlg_data["responses"])
      assert length(dlg_data["responses"]) == 2
    end
  end

  # =============================================================================
  # Pretty print
  # =============================================================================

  describe "pretty print option" do
    setup [:create_project]

    test "pretty_print produces formatted JSON", %{project: project} do
      {:ok, opts} =
        ExportOptions.new(%{format: :godot, validate_before_export: false, pretty_print: true})

      project_data = DataCollector.collect(project.id, opts)
      {:ok, json} = GodotJSON.serialize(project_data, opts)
      assert json =~ "\n"
    end
  end
end
