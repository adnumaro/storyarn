defmodule Storyarn.Exports.Serializers.StoryarnJSONTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports
  alias Storyarn.Exports.{DataCollector, ExportOptions}
  alias Storyarn.Exports.Serializers.StoryarnJSON

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  # =============================================================================
  # Setup
  # =============================================================================

  defp create_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  defp default_opts do
    {:ok, opts} = ExportOptions.new(%{format: :storyarn, validate_before_export: false})
    opts
  end

  defp export_and_decode(project, opts \\ nil) do
    opts = opts || default_opts()
    project_data = DataCollector.collect(project.id, opts)
    {:ok, json} = StoryarnJSON.serialize(project_data, opts)
    Jason.decode!(json)
  end

  # =============================================================================
  # Behaviour callbacks
  # =============================================================================

  describe "behaviour callbacks" do
    test "content_type returns application/json" do
      assert StoryarnJSON.content_type() == "application/json"
    end

    test "file_extension returns json" do
      assert StoryarnJSON.file_extension() == "json"
    end

    test "format_label returns human-readable name" do
      assert StoryarnJSON.format_label() == "Storyarn JSON"
    end

    test "supported_sections lists all sections" do
      sections = StoryarnJSON.supported_sections()
      assert :sheets in sections
      assert :flows in sections
      assert :scenes in sections
      assert :screenplays in sections
      assert :localization in sections
      assert :assets in sections
    end

    test "serialize_to_file returns not_implemented" do
      assert {:error, :not_implemented} = StoryarnJSON.serialize_to_file(nil, "", nil, [])
    end
  end

  # =============================================================================
  # Empty project (minimal valid export)
  # =============================================================================

  describe "empty project export" do
    setup [:create_project]

    test "produces valid JSON with required envelope", %{project: project} do
      result = export_and_decode(project)

      assert is_binary(result["storyarn_version"])
      assert result["export_version"] == "1.0.0"
      assert is_binary(result["exported_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(result["exported_at"])
    end

    test "serializes project section", %{project: project} do
      result = export_and_decode(project)

      assert result["project"]["id"] == to_string(project.id)
      assert result["project"]["name"] == project.name
      assert result["project"]["slug"] == project.slug
      assert is_map(result["project"]["settings"])
    end

    test "empty sections produce empty arrays", %{project: project} do
      result = export_and_decode(project)

      assert result["sheets"] == []
      assert result["flows"] == []
      assert result["scenes"] == []
      assert result["screenplays"] == []
      assert result["assets"]["items"] == []
    end

    test "metadata has zero counts for empty project", %{project: project} do
      result = export_and_decode(project)

      stats = result["metadata"]["statistics"]
      assert stats["sheet_count"] == 0
      assert stats["flow_count"] == 0
      assert stats["node_count"] == 0
      assert stats["scene_count"] == 0
    end
  end

  # =============================================================================
  # ID stringification
  # =============================================================================

  describe "ID stringification" do
    setup [:create_project]

    test "all IDs are serialized as strings", %{project: project} do
      sheet = sheet_fixture(project)
      _block = block_fixture(sheet)
      flow = flow_fixture(project)
      _node = node_fixture(flow)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene)

      result = export_and_decode(project)

      # Project
      assert is_binary(result["project"]["id"])

      # Sheet + block
      exported_sheet = hd(result["sheets"])
      assert is_binary(exported_sheet["id"])
      exported_block = hd(exported_sheet["blocks"])
      assert is_binary(exported_block["id"])

      # Flow + node
      exported_flow = hd(result["flows"])
      assert is_binary(exported_flow["id"])
      exported_node = hd(exported_flow["nodes"])
      assert is_binary(exported_node["id"])

      # Scene + pin
      exported_scene = hd(result["scenes"])
      assert is_binary(exported_scene["id"])
      exported_pin = hd(exported_scene["pins"])
      assert is_binary(exported_pin["id"])
    end

    test "nil IDs remain null", %{project: project} do
      _sheet = sheet_fixture(project)

      result = export_and_decode(project)
      exported_sheet = hd(result["sheets"])

      assert is_nil(exported_sheet["parent_id"])
      assert is_nil(exported_sheet["avatar_asset_id"])
    end
  end

  # =============================================================================
  # Sheets serialization
  # =============================================================================

  describe "sheets serialization" do
    setup [:create_project]

    test "serializes sheet fields", %{project: project} do
      _sheet = sheet_fixture(project, %{name: "Hero", description: "Main character"})

      result = export_and_decode(project)
      exported = hd(result["sheets"])

      assert exported["name"] == "Hero"
      assert exported["description"] == "Main character"
      assert is_binary(exported["shortcut"])
      assert is_integer(exported["position"])
    end

    test "serializes blocks within sheets", %{project: project} do
      sheet = sheet_fixture(project)

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "100"}
        })

      result = export_and_decode(project)
      exported_block = result["sheets"] |> hd() |> Map.get("blocks") |> hd()

      assert exported_block["type"] == "number"
      assert exported_block["config"]["label"] == "Health"
      assert is_boolean(exported_block["is_constant"])
    end

    test "serializes table blocks with columns and rows", %{project: project} do
      sheet = sheet_fixture(project)
      _table = table_block_fixture(sheet)

      result = export_and_decode(project)

      exported_block =
        result["sheets"]
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "table"))

      assert is_map(exported_block["table_data"])
      assert is_list(exported_block["table_data"]["columns"])
      assert is_list(exported_block["table_data"]["rows"])
    end
  end

  # =============================================================================
  # Flows serialization
  # =============================================================================

  describe "flows serialization" do
    setup [:create_project]

    test "serializes flow fields", %{project: project} do
      _flow = flow_fixture(project, %{name: "Main Story"})

      result = export_and_decode(project)
      exported = hd(result["flows"])

      assert exported["name"] == "Main Story"
      assert is_binary(exported["shortcut"])
      assert is_list(exported["nodes"])
      assert is_list(exported["connections"])
    end

    test "serializes nodes with data", %{project: project} do
      flow = flow_fixture(project)

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello!", "speaker" => "Hero"}
        })

      result = export_and_decode(project)
      nodes = result["flows"] |> hd() |> Map.get("nodes")
      exported_node = Enum.find(nodes, &(&1["type"] == "dialogue"))

      assert exported_node["type"] == "dialogue"
      assert exported_node["data"]["text"] == "Hello!"
      assert is_number(exported_node["position_x"])
      assert is_number(exported_node["position_y"])
    end

    test "serializes flow connections", %{project: project} do
      flow = flow_fixture(project)
      # flow_fixture auto-creates an entry node, so use dialogue nodes for connection test
      node1 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "A"}})
      node2 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "B"}})
      _conn = Storyarn.FlowsFixtures.connection_fixture(flow, node1, node2)

      result = export_and_decode(project)
      exported_conn = result["flows"] |> hd() |> Map.get("connections") |> hd()

      assert is_binary(exported_conn["id"])
      assert exported_conn["source_node_id"] == to_string(node1.id)
      assert exported_conn["target_node_id"] == to_string(node2.id)
      assert is_binary(exported_conn["source_pin"])
      assert is_binary(exported_conn["target_pin"])
    end

    test "dialogue node instruction parsing adds instruction_assignments", %{project: project} do
      instruction_json =
        Jason.encode!([
          %{"sheet" => "mc", "variable" => "health", "operator" => "add", "value" => "10"}
        ])

      flow = flow_fixture(project)

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "You found a potion!",
            "responses" => [
              %{"id" => "r1", "text" => "Drink it", "instruction" => instruction_json}
            ]
          }
        })

      result = export_and_decode(project)
      nodes = result["flows"] |> hd() |> Map.get("nodes")
      exported_node = Enum.find(nodes, &(&1["type"] == "dialogue"))
      response = hd(exported_node["data"]["responses"])

      assert is_list(response["instruction_assignments"])
      assert length(response["instruction_assignments"]) == 1
      assert hd(response["instruction_assignments"])["operator"] == "add"
    end
  end

  # =============================================================================
  # Scenes serialization
  # =============================================================================

  describe "scenes serialization" do
    setup [:create_project]

    test "serializes scene with sub-entities", %{project: project} do
      scene = scene_fixture(project, %{name: "World Map"})
      _layer = layer_fixture(scene)
      pin1 = pin_fixture(scene)
      pin2 = pin_fixture(scene)
      _zone = zone_fixture(scene)
      _annotation = annotation_fixture(scene)
      _conn = connection_fixture(scene, pin1, pin2)

      result = export_and_decode(project)
      exported = hd(result["scenes"])

      assert exported["name"] == "World Map"
      assert exported["layers"] != []
      assert Enum.count(exported["pins"]) == 2
      assert Enum.count(exported["zones"]) == 1
      assert Enum.count(exported["annotations"]) == 1
      assert Enum.count(exported["connections"]) == 1
    end

    test "serializes pin fields", %{project: project} do
      scene = scene_fixture(project)

      _pin =
        pin_fixture(scene, %{"label" => "Castle", "position_x" => 30.0, "position_y" => 40.0})

      result = export_and_decode(project)
      exported_pin = result["scenes"] |> hd() |> Map.get("pins") |> hd()

      assert exported_pin["label"] == "Castle"
      assert exported_pin["position_x"] == 30.0
      assert exported_pin["position_y"] == 40.0
    end

    test "serializes zone fields", %{project: project} do
      scene = scene_fixture(project)
      _zone = zone_fixture(scene, %{"name" => "Forest"})

      result = export_and_decode(project)
      exported_zone = result["scenes"] |> hd() |> Map.get("zones") |> hd()

      assert exported_zone["name"] == "Forest"
      assert is_list(exported_zone["vertices"])
    end
  end

  # =============================================================================
  # Screenplays serialization
  # =============================================================================

  describe "screenplays serialization" do
    setup [:create_project]

    test "serializes screenplay with elements", %{project: project} do
      sp = screenplay_fixture(project, %{name: "Act 1"})
      _el = element_fixture(sp, %{type: "action", content: "The hero enters."})

      result = export_and_decode(project)
      exported = hd(result["screenplays"])

      assert exported["name"] == "Act 1"
      assert length(exported["elements"]) == 1

      el = hd(exported["elements"])
      assert el["type"] == "action"
      assert el["content"] == "The hero enters."
    end

    test "includes draft fields", %{project: project} do
      _sp = screenplay_fixture(project)

      result = export_and_decode(project)
      exported = hd(result["screenplays"])

      assert Map.has_key?(exported, "draft_label")
      assert Map.has_key?(exported, "draft_status")
      assert Map.has_key?(exported, "draft_of_id")
    end
  end

  # =============================================================================
  # Assets serialization
  # =============================================================================

  describe "assets serialization" do
    setup [:create_project]

    test "serializes assets with metadata", %{project: project, user: user} do
      _asset =
        image_asset_fixture(project, user, %{
          filename: "hero.png",
          metadata: %{"width" => 512, "height" => 512}
        })

      result = export_and_decode(project)
      assets = result["assets"]

      assert assets["mode"] == "references"
      assert length(assets["items"]) == 1

      item = hd(assets["items"])
      assert item["filename"] == "hero.png"
      assert item["metadata"]["width"] == 512
      assert is_binary(item["key"])
    end
  end

  # =============================================================================
  # Localization serialization
  # =============================================================================

  describe "localization serialization" do
    setup [:create_project]

    test "serializes languages", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      result = export_and_decode(project)
      loc = result["localization"]

      assert loc["source_language"] == "en"
      assert length(loc["languages"]) == 2
      assert Enum.any?(loc["languages"], &(&1["locale_code"] == "en"))
      assert Enum.any?(loc["languages"], &(&1["locale_code"] == "es"))
    end

    test "serializes localized texts grouped by source", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      source_id = System.unique_integer([:positive])

      _text_en =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: source_id,
          source_field: "text",
          source_text: "Hello",
          locale_code: "en",
          translated_text: "Hello",
          status: "final"
        })

      _text_es =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: source_id,
          source_field: "text",
          source_text: "Hello",
          locale_code: "es",
          translated_text: "Hola",
          status: "in_progress"
        })

      result = export_and_decode(project)
      strings = result["localization"]["strings"]

      assert length(strings) == 1
      entry = hd(strings)
      assert entry["source_type"] == "flow_node"
      assert entry["source_field"] == "text"
      assert is_map(entry["translations"])
      assert entry["translations"]["es"]["translated_text"] == "Hola"
    end
  end

  # =============================================================================
  # Include/exclude flags
  # =============================================================================

  describe "include/exclude flags" do
    setup [:create_project]

    test "excluding sheets omits the section", %{project: project} do
      _sheet = sheet_fixture(project)

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_sheets: false,
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      refute Map.has_key?(result, "sheets")
    end

    test "excluding flows omits the section", %{project: project} do
      _flow = flow_fixture(project)

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_flows: false,
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      refute Map.has_key?(result, "flows")
    end

    test "excluding scenes omits the section", %{project: project} do
      _scene = scene_fixture(project)

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_scenes: false,
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      refute Map.has_key?(result, "scenes")
    end

    test "excluding screenplays omits the section", %{project: project} do
      _sp = screenplay_fixture(project)

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_screenplays: false,
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      refute Map.has_key?(result, "screenplays")
    end

    test "project and metadata always present", %{project: project} do
      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_sheets: false,
          include_flows: false,
          include_scenes: false,
          include_screenplays: false,
          include_localization: false,
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      assert is_map(result["project"])
      assert is_map(result["metadata"])
    end
  end

  # =============================================================================
  # Selective export (specific IDs)
  # =============================================================================

  describe "selective export" do
    setup [:create_project]

    test "exports only specified sheet_ids", %{project: project} do
      sheet1 = sheet_fixture(project, %{name: "Hero"})
      _sheet2 = sheet_fixture(project, %{name: "Villain"})

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          sheet_ids: [sheet1.id],
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      assert length(result["sheets"]) == 1
      assert hd(result["sheets"])["name"] == "Hero"
    end

    test "exports only specified flow_ids", %{project: project} do
      flow1 = flow_fixture(project, %{name: "Chapter 1"})
      _flow2 = flow_fixture(project, %{name: "Chapter 2"})

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          flow_ids: [flow1.id],
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      assert length(result["flows"]) == 1
      assert hd(result["flows"])["name"] == "Chapter 1"
    end

    test "exports only specified scene_ids", %{project: project} do
      scene1 = scene_fixture(project, %{name: "World"})
      _scene2 = scene_fixture(project, %{name: "Dungeon"})

      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          scene_ids: [scene1.id],
          validate_before_export: false
        })

      result = export_and_decode(project, opts)

      assert length(result["scenes"]) == 1
      assert hd(result["scenes"])["name"] == "World"
    end
  end

  # =============================================================================
  # ExportOptions
  # =============================================================================

  describe "ExportOptions" do
    test "new/1 with valid format" do
      assert {:ok, %ExportOptions{format: :storyarn}} = ExportOptions.new(%{format: :storyarn})
    end

    test "new/1 with string keys" do
      assert {:ok, %ExportOptions{format: :storyarn}} =
               ExportOptions.new(%{"format" => "storyarn"})
    end

    test "new/1 with invalid format returns error" do
      assert {:error, {:invalid_format, :nope}} = ExportOptions.new(%{format: :nope})
    end

    test "new/1 with invalid asset mode returns error" do
      assert {:error, {:invalid_asset_mode, :nope}} =
               ExportOptions.new(%{format: :storyarn, include_assets: :nope})
    end

    test "include_section? checks boolean flags" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_sheets: false})
      refute ExportOptions.include_section?(opts, :sheets)
      assert ExportOptions.include_section?(opts, :flows)
    end
  end

  # =============================================================================
  # Full pipeline (facade integration)
  # =============================================================================

  describe "Exports.export_project/2 integration" do
    setup [:create_project]

    test "exports a project through the facade", %{project: project} do
      assert {:ok, json} =
               Exports.export_project(project, %{format: :storyarn, validate_before_export: false})

      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert decoded["project"]["id"] == to_string(project.id)
    end

    test "returns error for unknown format", %{project: project} do
      assert {:error, {:invalid_format, :nope}} =
               Exports.export_project(project, %{format: :nope})
    end
  end

  # =============================================================================
  # Pretty print
  # =============================================================================

  describe "pretty print option" do
    setup [:create_project]

    test "pretty_print: true produces formatted JSON", %{project: project} do
      {:ok, opts} =
        ExportOptions.new(%{format: :storyarn, pretty_print: true, validate_before_export: false})

      project_data = DataCollector.collect(project.id, opts)
      {:ok, json} = StoryarnJSON.serialize(project_data, opts)

      assert json =~ "\n"
    end

    test "pretty_print: false produces compact JSON", %{project: project} do
      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          pretty_print: false,
          validate_before_export: false
        })

      project_data = DataCollector.collect(project.id, opts)
      {:ok, json} = StoryarnJSON.serialize(project_data, opts)

      refute json =~ "\n"
    end
  end
end
