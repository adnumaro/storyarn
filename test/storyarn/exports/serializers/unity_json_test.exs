defmodule Storyarn.Exports.Serializers.UnityJSONTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.UnityJSON

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
    {:ok, opts} = ExportOptions.new(%{format: :unity, validate_before_export: false})
    opts
  end

  defp export_and_decode(project, opts \\ nil) do
    opts = opts || default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, json} = UnityJSON.serialize(project_data, opts)
    Jason.decode!(json)
  end

  # =============================================================================
  # Behaviour callbacks
  # =============================================================================

  describe "behaviour callbacks" do
    test "content_type returns application/json" do
      assert UnityJSON.content_type() == "application/json"
    end

    test "file_extension returns json" do
      assert UnityJSON.file_extension() == "json"
    end

    test "format_label returns human-readable name" do
      assert UnityJSON.format_label() == "Unity Dialogue System (JSON)"
    end

    test "supported_sections lists flows and sheets" do
      sections = UnityJSON.supported_sections()
      assert :flows in sections
      assert :sheets in sections
    end

    test "serialize_to_file returns not_implemented" do
      assert {:error, :not_implemented} = UnityJSON.serialize_to_file(nil, "", nil, [])
    end
  end

  # =============================================================================
  # Empty project
  # =============================================================================

  describe "empty project export" do
    setup [:create_project]

    test "produces valid JSON with required envelope", %{project: project} do
      result = export_and_decode(project)
      assert result["format"] == "unity_dialogue_system"
      assert result["version"] == "1.0.0"
      assert is_binary(result["storyarn_version"])
    end

    test "has database structure", %{project: project} do
      result = export_and_decode(project)
      assert is_map(result["database"])
      assert is_list(result["database"]["actors"])
      assert is_list(result["database"]["conversations"])
      assert is_list(result["database"]["variables"])
    end
  end

  # =============================================================================
  # Actors from sheets
  # =============================================================================

  describe "actors from sheets" do
    setup [:create_project]

    test "sheets become actors with sequential IDs", %{project: project} do
      _sheet1 = sheet_fixture(project, %{name: "Hero"})
      _sheet2 = sheet_fixture(project, %{name: "Villain"})

      result = export_and_decode(project)
      actors = result["database"]["actors"]
      assert length(actors) == 2

      ids = Enum.map(actors, & &1["id"])
      assert ids == Enum.sort(ids)
      assert Enum.all?(ids, &is_integer/1)
    end

    test "actor has name, shortcut, and fields", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Jaime"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      result = export_and_decode(project)
      actor = hd(result["database"]["actors"])
      assert actor["name"] == "Jaime"
      assert actor["shortcut"] == sheet.shortcut
      assert is_map(actor["fields"])
    end
  end

  # =============================================================================
  # Conversations from flows
  # =============================================================================

  describe "conversations from flows" do
    setup [:create_project]

    test "flows become conversations", %{project: project} do
      flow = flow_fixture(project, %{name: "Act 1"})

      result = export_and_decode(project)
      convs = result["database"]["conversations"]
      assert length(convs) == 1
      conv = hd(convs)
      assert conv["title"] == flow.name
      assert conv["shortcut"] == flow.shortcut
      assert is_list(conv["entries"])
    end

    test "dialogue node becomes entry with text", %{project: project} do
      flow = flow_fixture(project, %{name: "Dialogue Test"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello world!",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      result = export_and_decode(project)
      entries = hd(result["database"]["conversations"])["entries"]
      dialogue_entry = Enum.find(entries, &(&1["node_type"] == "dialogue"))
      assert dialogue_entry
      assert dialogue_entry["dialogue_text"] == "Hello world!"
    end

    test "dialogue responses become child entries", %{project: project} do
      flow = flow_fixture(project, %{name: "Response Test"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose wisely",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{"id" => "r1", "text" => "Option A", "condition" => nil, "instruction" => nil},
              %{"id" => "r2", "text" => "Option B", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      result = export_and_decode(project)
      entries = hd(result["database"]["conversations"])["entries"]
      response_entries = Enum.filter(entries, &(&1["node_type"] == "response"))
      assert length(response_entries) == 2
    end

    test "entry node marked as root", %{project: project} do
      _flow = flow_fixture(project, %{name: "Root Test"})

      result = export_and_decode(project)
      entries = hd(result["database"]["conversations"])["entries"]
      entry_node = Enum.find(entries, &(&1["node_type"] == "entry"))
      assert entry_node["is_root"] == true
    end
  end

  # =============================================================================
  # Variables
  # =============================================================================

  describe "variables" do
    setup [:create_project]

    test "variables from sheets appear in database", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      result = export_and_decode(project)
      vars = result["database"]["variables"]
      assert vars != []

      var = hd(vars)
      assert is_binary(var["name"])
      assert var["type"] == "number"
      assert var["initial_value"] == 100
    end
  end

  # =============================================================================
  # Condition and instruction expressions
  # =============================================================================

  describe "expressions" do
    setup [:create_project]

    test "condition node has conditions field", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "Expr Flow"})
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
              %{"id" => "true", "value" => "true", "label" => "True"},
              %{"id" => "false", "value" => "false", "label" => "False"}
            ]
          }
        })

      connection_fixture(flow, entry, condition)

      result = export_and_decode(project)
      entries = hd(result["database"]["conversations"])["entries"]
      cond_entry = Enum.find(entries, &(&1["node_type"] == "condition"))
      assert cond_entry
      assert is_binary(cond_entry["conditions"])
    end

    test "instruction node has user_script field", %{project: project} do
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
      entries = hd(result["database"]["conversations"])["entries"]
      inst_entry = Enum.find(entries, &(&1["node_type"] == "instruction"))
      assert inst_entry
      assert is_binary(inst_entry["user_script"])
    end
  end

  # =============================================================================
  # Pretty print
  # =============================================================================

  describe "pretty print option" do
    setup [:create_project]

    test "pretty_print produces formatted JSON", %{project: project} do
      {:ok, opts} =
        ExportOptions.new(%{format: :unity, validate_before_export: false, pretty_print: true})

      project_data = DataCollector.collect(project.id, opts)
      {:ok, json} = UnityJSON.serialize(project_data, opts)
      assert json =~ "\n"
    end
  end
end
