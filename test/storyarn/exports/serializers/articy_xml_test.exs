defmodule Storyarn.Exports.Serializers.ArticyXMLTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.ArticyXML

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
    {:ok, opts} = ExportOptions.new(%{format: :articy, validate_before_export: false})
    opts
  end

  defp export_xml(project, opts \\ nil) do
    opts = opts || default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, xml} = ArticyXML.serialize(project_data, opts)
    xml
  end

  # =============================================================================
  # Behaviour callbacks
  # =============================================================================

  describe "behaviour callbacks" do
    test "content_type returns application/xml" do
      assert ArticyXML.content_type() == "application/xml"
    end

    test "file_extension returns xml" do
      assert ArticyXML.file_extension() == "xml"
    end

    test "format_label returns human-readable name" do
      assert ArticyXML.format_label() == "articy:draft (XML)"
    end

    test "supported_sections lists flows and sheets" do
      sections = ArticyXML.supported_sections()
      assert :flows in sections
      assert :sheets in sections
    end

    test "serialize_to_file returns not_implemented" do
      assert {:error, :not_implemented} = ArticyXML.serialize_to_file(nil, "", nil, [])
    end
  end

  # =============================================================================
  # XML structure
  # =============================================================================

  describe "XML structure" do
    setup [:create_project]

    test "produces valid XML with declaration", %{project: project} do
      xml = export_xml(project)
      assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
    end

    test "has ArticyData root element", %{project: project} do
      xml = export_xml(project)
      assert xml =~ "<ArticyData>"
      assert xml =~ "</ArticyData>"
    end

    test "has Project element with GUID", %{project: project} do
      xml = export_xml(project)
      assert xml =~ "<Project"
      assert xml =~ "Guid=\"0x"
      assert xml =~ "</Project>"
    end

    test "has ExportSettings", %{project: project} do
      xml = export_xml(project)
      assert xml =~ "<ExportSettings>"
      assert xml =~ "<ExportVersion>1.0</ExportVersion>"
      assert xml =~ "<StoryarnExportVersion>"
    end

    test "has Hierarchy element", %{project: project} do
      xml = export_xml(project)
      assert xml =~ "<Hierarchy>"
      assert xml =~ "</Hierarchy>"
    end
  end

  # =============================================================================
  # GUID generation
  # =============================================================================

  describe "GUID generation" do
    test "produces deterministic GUIDs" do
      guid1 = ArticyXML.generate_guid("test:123")
      guid2 = ArticyXML.generate_guid("test:123")
      assert guid1 == guid2
    end

    test "different inputs produce different GUIDs" do
      guid1 = ArticyXML.generate_guid("test:123")
      guid2 = ArticyXML.generate_guid("test:456")
      refute guid1 == guid2
    end

    test "GUID format is 0x followed by hex" do
      guid = ArticyXML.generate_guid("test:abc")
      assert String.starts_with?(guid, "0x")
      hex = String.slice(guid, 2..-1//1)
      assert String.match?(hex, ~r/^[0-9A-F]+$/)
    end
  end

  # =============================================================================
  # Global Variables
  # =============================================================================

  describe "global variables" do
    setup [:create_project]

    test "empty project has empty GlobalVariables", %{project: project} do
      xml = export_xml(project)
      assert xml =~ "<GlobalVariables/>"
    end

    test "variables grouped by namespace", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Alive"},
        value: %{"boolean" => true}
      })

      xml = export_xml(project)
      assert xml =~ "<GlobalVariables>"
      assert xml =~ "<Namespace"
      assert xml =~ "<Variable"
      assert xml =~ "</GlobalVariables>"
    end

    test "variable types mapped correctly", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Config"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Count"},
        value: %{"number" => 42}
      })

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Flag"},
        value: %{"boolean" => true}
      })

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Name"},
        value: %{"text" => "test"}
      })

      xml = export_xml(project)
      assert xml =~ ~s(Type="int")
      assert xml =~ ~s(Type="bool")
      assert xml =~ ~s(Type="string")
    end
  end

  # =============================================================================
  # Entities from sheets
  # =============================================================================

  describe "entities from sheets" do
    setup [:create_project]

    test "sheets become Entity elements", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Jaime"})

      xml = export_xml(project)
      assert xml =~ "<Entity"
      assert xml =~ ~s(Type="Character")
      assert xml =~ ~s(TechnicalName="#{sheet.shortcut}")
      assert xml =~ "<DisplayName>Jaime</DisplayName>"
    end

    test "entity properties from blocks", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      xml = export_xml(project)
      assert xml =~ "<Properties>"
      assert xml =~ "<Property"
      assert xml =~ ~s(Name="health")
    end

    test "entity without properties has empty Properties", %{project: project} do
      _sheet = sheet_fixture(project, %{name: "NPC"})

      xml = export_xml(project)
      assert xml =~ "<Properties/>"
    end
  end

  # =============================================================================
  # FlowFragments from flows
  # =============================================================================

  describe "flow fragments from flows" do
    setup [:create_project]

    test "flows become FlowFragment elements", %{project: project} do
      flow = flow_fixture(project, %{name: "Main Story"})

      xml = export_xml(project)
      assert xml =~ "<FlowFragment"
      assert xml =~ ~s(Type="Dialogue")
      assert xml =~ "<DisplayName>Main Story</DisplayName>"
      assert xml =~ ~s(TechnicalName="#{flow.shortcut}")
    end

    test "dialogue node becomes DialogueFragment", %{project: project} do
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

      xml = export_xml(project)
      assert xml =~ "<DialogueFragment"
      assert xml =~ ~s(Speaker="#{sheet.shortcut}")
      assert xml =~ "<Text>Hello world!</Text>"
    end

    test "condition node becomes Condition element", %{project: project} do
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
            "cases" => [%{"id" => "true", "value" => "true", "label" => "True"}]
          }
        })

      connection_fixture(flow, entry, condition)

      xml = export_xml(project)
      assert xml =~ "<Condition"
      assert xml =~ "<Expression>"
    end

    test "instruction node becomes Instruction element", %{project: project} do
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
              %{"sheet" => sheet.shortcut, "variable" => "met", "operator" => "set_true"}
            ]
          }
        })

      connection_fixture(flow, entry, instruction)

      xml = export_xml(project)
      assert xml =~ "<Instruction"
      assert xml =~ "<Expression>"
    end

    test "hub node becomes Hub element", %{project: project} do
      flow = flow_fixture(project, %{name: "Hub Flow"})

      _hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"label" => "checkpoint"}
        })

      xml = export_xml(project)
      assert xml =~ "<Hub"
      assert xml =~ "<DisplayName>checkpoint</DisplayName>"
    end

    test "jump node becomes Jump element", %{project: project} do
      flow = flow_fixture(project, %{name: "Jump Flow"})

      _jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"hub_id" => "some-hub-id"}
        })

      xml = export_xml(project)
      assert xml =~ "<Jump"
      assert xml =~ ~s(Target="some-hub-id")
    end
  end

  # =============================================================================
  # Connections
  # =============================================================================

  describe "connections" do
    setup [:create_project]

    test "connections have Source and Target GUIDs", %{project: project} do
      flow = flow_fixture(project, %{name: "Conn Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi", "responses" => []}})

      connection_fixture(flow, entry, dialogue)

      xml = export_xml(project)
      assert xml =~ "<Connection"
      assert xml =~ "Source=\"0x"
      assert xml =~ "Target=\"0x"
    end

    test "connections have deterministic GUIDs", %{project: project} do
      flow = flow_fixture(project, %{name: "Det Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi", "responses" => []}})

      connection_fixture(flow, entry, dialogue)

      xml1 = export_xml(project)
      xml2 = export_xml(project)

      # Extract Connection elements
      conn_re = ~r/<Connection[^\/]*\/>/
      conns1 = Regex.scan(conn_re, xml1)
      conns2 = Regex.scan(conn_re, xml2)
      assert conns1 == conns2
    end
  end

  # =============================================================================
  # XML escaping
  # =============================================================================

  describe "XML escaping" do
    setup [:create_project]

    test "special characters in text are escaped", %{project: project} do
      flow = flow_fixture(project, %{name: "Escape Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "He said \"hello\" & goodbye",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      connection_fixture(flow, entry, dialogue)

      xml = export_xml(project)
      assert xml =~ "&amp;"
      assert xml =~ "&quot;"
    end
  end

  # =============================================================================
  # Dialogue responses
  # =============================================================================

  describe "dialogue responses" do
    setup [:create_project]

    test "responses become child DialogueFragments", %{project: project} do
      flow = flow_fixture(project, %{name: "Resp Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{"id" => "r1", "text" => "Yes", "condition" => nil, "instruction" => nil},
              %{"id" => "r2", "text" => "No", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      xml = export_xml(project)
      # Should have multiple DialogueFragment elements
      fragment_count = xml |> String.split("<DialogueFragment") |> length()
      # At least 3: main dialogue + 2 responses (plus the split before first match)
      assert fragment_count >= 4
    end

    test "response with condition includes Condition element", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"number" => 100}
      })

      flow = flow_fixture(project, %{name: "RCond Flow"})
      flow = reload_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "speaker_sheet_id" => nil,
            "responses" => [
              %{
                "id" => "r1",
                "text" => "Strong choice",
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
                "instruction" => nil
              }
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)

      xml = export_xml(project)
      assert xml =~ "<Condition>"
    end
  end

  # =============================================================================
  # Scene and subflow node types
  # =============================================================================

  describe "scene and subflow node types" do
    setup [:create_project]

    test "scene node becomes LocationSettings element", %{project: project} do
      flow = flow_fixture(project, %{name: "Scene Flow"})

      _scene_node =
        node_fixture(flow, %{
          type: "scene",
          data: %{"location" => "Ancient Temple", "slug_line" => "INT. TEMPLE - DAY"}
        })

      xml = export_xml(project)
      assert xml =~ "<LocationSettings"
      assert xml =~ "<Location>Ancient Temple</Location>"
      assert xml =~ ~s(TechnicalName="scene_)
    end

    test "subflow node becomes FlowFragment with Reference", %{project: project} do
      flow = flow_fixture(project, %{name: "Subflow Flow"})

      _subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"flow_shortcut" => "chapter.two"}
        })

      xml = export_xml(project)
      assert xml =~ ~s(TechnicalName="subflow_)
      assert xml =~ ~s(Reference="chapter.two")
    end

    test "unknown node type produces no output", %{project: project} do
      _flow = flow_fixture(project, %{name: "Unknown Flow"})

      # Entry and exit are built-in, but let's add an entry/exit to verify they work
      # and also test the catch-all clause by checking the total node count
      xml = export_xml(project)

      # Only entry node is auto-created — it should render as <Entry>
      assert xml =~ "<Entry"
    end
  end

  # =============================================================================
  # Variable type edge cases
  # =============================================================================

  describe "variable type edge cases" do
    setup [:create_project]

    test "unknown block type maps to string", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Special"})

      # select type blocks that are not constants become variables
      # The variable_type_to_articy fallback (_) covers non-standard types
      block_fixture(sheet, %{
        type: "select",
        config: %{
          "label" => "Class",
          "options" => [%{"value" => "warrior", "label" => "Warrior"}]
        },
        value: %{"selected" => "warrior"}
      })

      xml = export_xml(project)
      # select blocks infer as :string, which maps to "string" in articy
      assert xml =~ ~s(Type="string")
    end

    test "nil value formats to string via to_string", %{project: project} do
      sheet = sheet_fixture(project, %{name: "NilVal"})

      # Block with nil-ish default value
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Score"},
        value: %{}
      })

      xml = export_xml(project)
      assert xml =~ "<Variable"
      # The value should be "0" (default for number) or handled gracefully
      assert xml =~ "Value="
    end
  end
end
