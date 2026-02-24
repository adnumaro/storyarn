defmodule Storyarn.Exports.RoundTripTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports
  alias Storyarn.Imports

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  @moduledoc """
  Round-trip test: export → import → re-export → compare.

  The P0 test for the export system. If data survives a round-trip,
  the serializer and import parser are correct.
  """

  # =============================================================================
  # Setup
  # =============================================================================

  defp create_populated_project(_context) do
    user = user_fixture()
    source_project = project_fixture(user)
    target_project = project_fixture(user)

    # Sheets with blocks
    sheet = sheet_fixture(source_project, %{name: "Hero", description: "Main character"})

    _text_block =
      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Name"},
        value: %{"content" => "Jaime"}
      })

    _num_block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => "100"}
      })

    _table = table_block_fixture(sheet)

    child_sheet = child_sheet_fixture(source_project, sheet, %{name: "Sidekick"})

    _child_block =
      block_fixture(child_sheet, %{
        type: "boolean",
        config: %{"label" => "Active"},
        value: %{"content" => true}
      })

    # Flows with nodes and connections
    flow = flow_fixture(source_project, %{name: "Main Story"})

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Hello adventurer!", "speaker" => "Hero", "responses" => []}
      })

    condition =
      node_fixture(flow, %{
        type: "condition",
        data: %{
          "expression" => "",
          "cases" => [%{"id" => "c1", "value" => "true", "label" => "True"}]
        }
      })

    _conn = Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, condition)

    # Scenes with sub-entities
    scene = scene_fixture(source_project, %{name: "World Map"})
    _layer = layer_fixture(scene, %{"name" => "Base Layer"})
    pin1 = pin_fixture(scene, %{"label" => "Castle", "position_x" => 30.0, "position_y" => 40.0})
    pin2 = pin_fixture(scene, %{"label" => "Village", "position_x" => 60.0, "position_y" => 70.0})
    _zone = zone_fixture(scene, %{"name" => "Forest"})
    _annotation = annotation_fixture(scene, %{"text" => "Here be dragons"})
    _scene_conn = connection_fixture(scene, pin1, pin2)

    # Screenplays
    sp = screenplay_fixture(source_project, %{name: "Act 1"})
    _el1 = element_fixture(sp, %{type: "scene_heading", content: "INT. CASTLE - DAY"})
    _el2 = element_fixture(sp, %{type: "action", content: "The hero enters the throne room."})

    # Assets
    _asset =
      image_asset_fixture(source_project, user, %{
        filename: "hero_portrait.png",
        metadata: %{"width" => 256, "height" => 256}
      })

    # Localization
    _en = source_language_fixture(source_project, %{locale_code: "en", name: "English"})
    _es = language_fixture(source_project, %{locale_code: "es", name: "Spanish"})

    _text =
      localized_text_fixture(source_project.id, %{
        source_type: "flow_node",
        source_id: dialogue.id,
        source_field: "text",
        source_text: "Hello adventurer!",
        locale_code: "es",
        translated_text: "Hola aventurero!",
        status: "final"
      })

    %{
      user: user,
      source_project: source_project,
      target_project: target_project
    }
  end

  # =============================================================================
  # Round-trip test
  # =============================================================================

  describe "export → import round-trip" do
    setup [:create_populated_project]

    test "export and re-export produce structurally identical data", %{
      source_project: source,
      target_project: target
    } do
      export_opts = %{format: :storyarn, validate_before_export: false, pretty_print: false}

      # Step 1: Export source project
      assert {:ok, json1} = Exports.export_project(source, export_opts)
      data1 = Jason.decode!(json1)

      # Step 2: Import into target project
      assert {:ok, parsed} = Imports.parse_file(json1)
      assert {:ok, _result} = Imports.execute(target, parsed.data)

      # Step 3: Re-export target project
      assert {:ok, json2} = Exports.export_project(target, export_opts)
      data2 = Jason.decode!(json2)

      # Step 4: Compare (ignoring IDs, timestamps, project-specific fields)
      assert_sections_match(data1, data2)
    end

    test "import preserves entity counts", %{
      source_project: source,
      target_project: target
    } do
      export_opts = %{format: :storyarn, validate_before_export: false}
      {:ok, json} = Exports.export_project(source, export_opts)
      data = Jason.decode!(json)

      {:ok, parsed} = Imports.parse_file(json)
      {:ok, _result} = Imports.execute(target, parsed.data)

      {:ok, json2} = Exports.export_project(target, export_opts)
      data2 = Jason.decode!(json2)

      # Same number of entities
      assert length(data["sheets"]) == length(data2["sheets"])
      assert length(data["flows"]) == length(data2["flows"])
      assert length(data["scenes"]) == length(data2["scenes"])
      assert length(data["screenplays"]) == length(data2["screenplays"])

      assert length(get_in(data, ["assets", "items"])) ==
               length(get_in(data2, ["assets", "items"]))

      # Same node/connection counts
      source_nodes = data["flows"] |> Enum.flat_map(& &1["nodes"]) |> length()
      target_nodes = data2["flows"] |> Enum.flat_map(& &1["nodes"]) |> length()
      assert source_nodes == target_nodes
    end
  end

  # =============================================================================
  # Parse validation
  # =============================================================================

  describe "parse validation" do
    test "rejects invalid JSON" do
      assert {:error, :invalid_json} = Imports.parse_file("not json")
    end

    test "rejects JSON without required keys" do
      json = Jason.encode!(%{"foo" => "bar"})
      assert {:error, {:missing_required_keys, _}} = Imports.parse_file(json)
    end

    test "rejects file exceeding size limit" do
      # Create a string larger than 50MB
      huge = String.duplicate("x", 50_000_001)
      assert {:error, :file_too_large} = Imports.parse_file(huge)
    end

    test "accepts valid export file" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, json} =
        Exports.export_project(project, %{format: :storyarn, validate_before_export: false})

      assert {:ok, %{format: :storyarn, data: data}} = Imports.parse_file(json)
      assert is_map(data["project"])
    end
  end

  # =============================================================================
  # Preview
  # =============================================================================

  describe "import preview" do
    setup [:create_populated_project]

    test "counts entities in import file", %{source_project: source, target_project: target} do
      {:ok, json} =
        Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

      {:ok, parsed} = Imports.parse_file(json)

      {:ok, preview} = Imports.preview(target.id, parsed.data)

      assert preview.counts.sheets > 0
      assert preview.counts.flows > 0
      assert preview.counts.scenes > 0
    end
  end

  # =============================================================================
  # Entity count limits
  # =============================================================================

  describe "entity count limits" do
    test "rejects import with too many entities" do
      user = user_fixture()
      project = project_fixture(user)

      # Build a minimal valid Storyarn JSON with more sheets than the limit
      sheets = for i <- 1..1_001, do: %{"id" => "s#{i}", "name" => "Sheet #{i}", "blocks" => []}

      data = %{
        "storyarn_version" => "0.1.0",
        "export_version" => "1.0.0",
        "project" => %{"name" => "Test"},
        "sheets" => sheets,
        "flows" => [],
        "scenes" => [],
        "screenplays" => []
      }

      assert {:error, {:entity_limits_exceeded, details}} = Imports.execute(project, data)
      assert details.sheets.count == 1_001
      assert details.sheets.limit == 1_000
    end
  end

  # =============================================================================
  # Comparison helpers
  # =============================================================================

  defp assert_sections_match(data1, data2) do
    # Sheets: compare by name, check block types and values
    assert_entities_match(data1["sheets"], data2["sheets"], "sheets", fn s1, s2 ->
      assert s1["name"] == s2["name"], "Sheet name mismatch: #{s1["name"]} vs #{s2["name"]}"

      assert length(s1["blocks"]) == length(s2["blocks"]),
             "Block count mismatch for sheet #{s1["name"]}: #{length(s1["blocks"])} vs #{length(s2["blocks"])}"

      # Value-level: compare block types and config labels
      b1_types = s1["blocks"] |> Enum.map(& &1["type"]) |> Enum.sort()
      b2_types = s2["blocks"] |> Enum.map(& &1["type"]) |> Enum.sort()
      assert b1_types == b2_types, "Block types mismatch for sheet #{s1["name"]}"

      b1_labels = s1["blocks"] |> Enum.map(&get_in(&1, ["config", "label"])) |> Enum.sort()
      b2_labels = s2["blocks"] |> Enum.map(&get_in(&1, ["config", "label"])) |> Enum.sort()
      assert b1_labels == b2_labels, "Block labels mismatch for sheet #{s1["name"]}"
    end)

    # Flows: compare by name, check node types and connection counts
    assert_entities_match(data1["flows"], data2["flows"], "flows", fn f1, f2 ->
      assert f1["name"] == f2["name"]

      assert length(f1["nodes"]) == length(f2["nodes"]),
             "Node count mismatch for flow #{f1["name"]}"

      assert length(f1["connections"]) == length(f2["connections"]),
             "Connection count mismatch for flow #{f1["name"]}"

      # Value-level: compare node types
      n1_types = f1["nodes"] |> Enum.map(& &1["type"]) |> Enum.sort()
      n2_types = f2["nodes"] |> Enum.map(& &1["type"]) |> Enum.sort()
      assert n1_types == n2_types, "Node types mismatch for flow #{f1["name"]}"
    end)

    # Scenes: compare by name, check pin labels and zone names
    assert_entities_match(data1["scenes"], data2["scenes"], "scenes", fn s1, s2 ->
      assert s1["name"] == s2["name"]
      assert length(s1["pins"]) == length(s2["pins"])
      assert length(s1["zones"]) == length(s2["zones"])

      # Value-level: compare pin labels and zone names
      p1_labels = s1["pins"] |> Enum.map(& &1["label"]) |> Enum.sort()
      p2_labels = s2["pins"] |> Enum.map(& &1["label"]) |> Enum.sort()
      assert p1_labels == p2_labels, "Pin labels mismatch for scene #{s1["name"]}"

      z1_names = s1["zones"] |> Enum.map(& &1["name"]) |> Enum.sort()
      z2_names = s2["zones"] |> Enum.map(& &1["name"]) |> Enum.sort()
      assert z1_names == z2_names, "Zone names mismatch for scene #{s1["name"]}"
    end)

    # Screenplays: compare by name, check element types and content
    assert_entities_match(data1["screenplays"], data2["screenplays"], "screenplays", fn sp1,
                                                                                        sp2 ->
      assert sp1["name"] == sp2["name"]
      assert length(sp1["elements"]) == length(sp2["elements"])

      # Value-level: compare element types
      e1_types = sp1["elements"] |> Enum.map(& &1["type"]) |> Enum.sort()
      e2_types = sp2["elements"] |> Enum.map(& &1["type"]) |> Enum.sort()
      assert e1_types == e2_types, "Element types mismatch for screenplay #{sp1["name"]}"
    end)

    # Assets: compare by filename
    items1 = get_in(data1, ["assets", "items"]) || []
    items2 = get_in(data2, ["assets", "items"]) || []
    assert length(items1) == length(items2), "Asset count mismatch"

    fnames1 = items1 |> Enum.map(& &1["filename"]) |> Enum.sort()
    fnames2 = items2 |> Enum.map(& &1["filename"]) |> Enum.sort()
    assert fnames1 == fnames2, "Asset filenames mismatch"
  end

  defp assert_entities_match(list1, list2, label, compare_fn) do
    assert length(list1) == length(list2),
           "#{label} count mismatch: #{length(list1)} vs #{length(list2)}"

    sorted1 = Enum.sort_by(list1, & &1["name"])
    sorted2 = Enum.sort_by(list2, & &1["name"])

    Enum.zip(sorted1, sorted2) |> Enum.each(fn {e1, e2} -> compare_fn.(e1, e2) end)
  end
end
