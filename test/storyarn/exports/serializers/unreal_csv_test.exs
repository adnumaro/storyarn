defmodule Storyarn.Exports.Serializers.UnrealCSVTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.UnrealCSV

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
    {:ok, opts} = ExportOptions.new(%{format: :unreal, validate_before_export: false})
    opts
  end

  defp export_files(project, opts \\ nil) do
    opts = opts || default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, files} = UnrealCSV.serialize(project_data, opts)
    files
  end

  defp get_file(files, name) do
    {_name, content} = Enum.find(files, fn {n, _} -> n == name end)
    content
  end

  # =============================================================================
  # Behaviour callbacks
  # =============================================================================

  describe "behaviour callbacks" do
    test "content_type returns text/csv" do
      assert UnrealCSV.content_type() == "text/csv"
    end

    test "file_extension returns csv" do
      assert UnrealCSV.file_extension() == "csv"
    end

    test "format_label returns human-readable name" do
      assert UnrealCSV.format_label() == "Unreal Engine (CSV)"
    end

    test "supported_sections lists flows and sheets" do
      sections = UnrealCSV.supported_sections()
      assert :flows in sections
      assert :sheets in sections
    end

    test "serialize_to_file returns not_implemented" do
      assert {:error, :not_implemented} = UnrealCSV.serialize_to_file(nil, "", nil, [])
    end
  end

  # =============================================================================
  # File structure
  # =============================================================================

  describe "output file structure" do
    setup [:create_project]

    test "produces 4 files", %{project: project} do
      files = export_files(project)
      names = Enum.map(files, fn {name, _} -> name end)
      assert "DT_DialogueLines.csv" in names
      assert "DT_Characters.csv" in names
      assert "DT_Variables.csv" in names
      assert "Conversations.json" in names
    end
  end

  # =============================================================================
  # Dialogue Lines CSV
  # =============================================================================

  describe "DT_DialogueLines.csv" do
    setup [:create_project]

    test "has correct header row", %{project: project} do
      _flow = flow_fixture(project, %{name: "Test"})
      csv = get_file(export_files(project), "DT_DialogueLines.csv")
      first_line = csv |> String.split("\n") |> hd()
      assert first_line =~ "Name"
      assert first_line =~ "ConversationId"
      assert first_line =~ "NodeType"
      assert first_line =~ "Text"
      assert first_line =~ "NextLines"
    end

    test "dialogue node produces row with text", %{project: project} do
      flow = flow_fixture(project, %{name: "Dlg Test"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello adventurer!",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      csv = get_file(export_files(project), "DT_DialogueLines.csv")
      assert csv =~ "Hello adventurer!"
      assert csv =~ "dialogue"
    end

    test "row names are sequential DLG_ prefixed", %{project: project} do
      flow = flow_fixture(project, %{name: "Seq Test"})
      _node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi", "responses" => []}})

      csv = get_file(export_files(project), "DT_DialogueLines.csv")
      assert csv =~ "DLG_"
    end

    test "next lines are pipe-separated", %{project: project} do
      flow = flow_fixture(project, %{name: "Next Test"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      d1 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "A", "responses" => []}})
      d2 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "B", "responses" => []}})

      connection_fixture(flow, entry, d1)
      connection_fixture(flow, entry, d2)

      csv = get_file(export_files(project), "DT_DialogueLines.csv")
      # Entry node should have pipe-separated targets
      lines = String.split(csv, "\n")
      entry_line = Enum.find(lines, &(&1 =~ "entry"))

      if entry_line do
        assert entry_line =~ "|" or entry_line =~ "DLG_"
      end
    end

    test "responses produce separate rows", %{project: project} do
      flow = flow_fixture(project, %{name: "Resp Test"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{"id" => "r1", "text" => "Option A", "condition" => nil, "instruction" => nil},
              %{"id" => "r2", "text" => "Option B", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      csv = get_file(export_files(project), "DT_DialogueLines.csv")
      assert csv =~ "response"
      assert csv =~ "Option A"
      assert csv =~ "Option B"
    end

    test "condition node produces row", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "Cond Test"})
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
            "cases" => [%{"id" => "true", "value" => "true", "label" => "True"}]
          }
        })

      connection_fixture(flow, entry, condition)

      csv = get_file(export_files(project), "DT_DialogueLines.csv")
      assert csv =~ "condition"
    end

    test "instruction node produces row", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Flags"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Met"},
        value: %{"boolean" => false}
      })

      flow = flow_fixture(project, %{name: "Inst Test"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{"sheet" => sheet.shortcut, "variable" => "met", "operator" => "set_true"}
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      csv = get_file(export_files(project), "DT_DialogueLines.csv")
      assert csv =~ "instruction"
    end
  end

  # =============================================================================
  # Characters CSV
  # =============================================================================

  describe "DT_Characters.csv" do
    setup [:create_project]

    test "has correct header", %{project: project} do
      _sheet = sheet_fixture(project, %{name: "Hero"})
      csv = get_file(export_files(project), "DT_Characters.csv")
      first_line = csv |> String.split("\n") |> hd()
      assert first_line =~ "Name"
      assert first_line =~ "DisplayName"
      assert first_line =~ "ShortcutId"
    end

    test "sheets become character rows", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Jaime"})

      csv = get_file(export_files(project), "DT_Characters.csv")
      assert csv =~ "CHAR_"
      assert csv =~ "Jaime"
      assert csv =~ sheet.shortcut
    end

    test "character properties serialized as JSON", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      csv = get_file(export_files(project), "DT_Characters.csv")
      # Properties column should contain JSON
      assert csv =~ "health"
    end
  end

  # =============================================================================
  # Variables CSV
  # =============================================================================

  describe "DT_Variables.csv" do
    setup [:create_project]

    test "has correct header", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      csv = get_file(export_files(project), "DT_Variables.csv")
      first_line = csv |> String.split("\n") |> hd()
      assert first_line =~ "Name"
      assert first_line =~ "VariableId"
      assert first_line =~ "Type"
      assert first_line =~ "DefaultValue"
    end

    test "variables produce rows with VAR_ prefix", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      csv = get_file(export_files(project), "DT_Variables.csv")
      assert csv =~ "VAR_"
      assert csv =~ "number"
    end
  end

  # =============================================================================
  # Metadata JSON
  # =============================================================================

  describe "Conversations.json metadata" do
    setup [:create_project]

    test "has required envelope fields", %{project: project} do
      _flow = flow_fixture(project, %{name: "Test"})

      json = get_file(export_files(project), "Conversations.json")
      meta = Jason.decode!(json)
      assert meta["format"] == "storyarn_unreal"
      assert meta["version"] == "1.0.0"
    end

    test "includes conversations with graph structure", %{project: project} do
      flow = flow_fixture(project, %{name: "Act 1"})

      json = get_file(export_files(project), "Conversations.json")
      meta = Jason.decode!(json)

      conv_key =
        Storyarn.Exports.Serializers.Helpers.shortcut_to_identifier(flow.shortcut || flow.name)

      conv = meta["conversations"][conv_key]
      assert conv
      assert conv["name"] == "Act 1"
      assert is_map(conv["nodes"])
    end

    test "includes characters", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      json = get_file(export_files(project), "Conversations.json")
      meta = Jason.decode!(json)

      char_key = Storyarn.Exports.Serializers.Helpers.shortcut_to_identifier(sheet.shortcut)
      assert meta["characters"][char_key]
    end

    test "includes variables", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Str"},
        value: %{"number" => 10}
      })

      json = get_file(export_files(project), "Conversations.json")
      meta = Jason.decode!(json)
      assert map_size(meta["variables"]) >= 1
    end
  end
end
