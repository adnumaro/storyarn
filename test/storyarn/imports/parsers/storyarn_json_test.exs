defmodule Storyarn.Imports.Parsers.StoryarnJSONTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Exports
  alias Storyarn.Flows
  alias Storyarn.Imports
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Localization

  # =============================================================================
  # Setup
  # =============================================================================

  defp setup_projects(_context) do
    user = user_fixture()
    source = project_fixture(user)
    target = project_fixture(user)
    %{user: user, source: source, target: target}
  end

  defp storyarn_plan(data) do
    %ImportPlan{
      format: :storyarn,
      parser_version: "1",
      source_kind: :file,
      data: data
    }
  end

  defp setup_with_data(%{source: source} = context) do
    # Create entities in source
    sheet = sheet_fixture(source, %{name: "Hero"})

    _block =
      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Name"},
        value: %{"content" => "Jaime"}
      })

    flow = flow_fixture(source, %{name: "Main Story"})
    _dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello!"}})

    scene = scene_fixture(source, %{name: "World Map"})
    _pin = pin_fixture(scene, %{"label" => "Castle", "position_x" => 10.0, "position_y" => 10.0})

    sp = screenplay_fixture(source, %{name: "Act 1"})
    _el = element_fixture(sp, %{type: "action", content: "The hero enters."})

    # Export source project
    {:ok, json} =
      Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

    {:ok, parsed} = Imports.parse_file(json)

    Map.merge(context, %{
      json: json,
      parsed: parsed,
      sheet: sheet,
      flow: flow,
      scene: scene,
      screenplay: sp
    })
  end

  # =============================================================================
  # Parse errors
  # =============================================================================

  describe "parse — error paths" do
    test "returns error for invalid JSON" do
      assert {:error, :invalid_json} = Imports.parse_file("not valid json {{{")
    end

    test "returns error for non-map JSON (array)" do
      json = Jason.encode!([1, 2, 3])
      assert {:error, :invalid_json_structure} = Imports.parse_file(json)
    end

    test "returns error for missing required keys" do
      json = Jason.encode!(%{"foo" => "bar"})
      assert {:error, {:missing_required_keys, missing}} = Imports.parse_file(json)
      assert "storyarn_version" in missing
      assert "export_version" in missing
      assert "project" in missing
    end

    test "accepts explicit null flow collections without crashing" do
      assert {:ok, _data} =
               minimal_import_data()
               |> Map.put("flows", nil)
               |> Jason.encode!()
               |> Imports.parse_file()

      assert {:ok, _data} =
               minimal_import_data()
               |> put_in(["flows", Access.at(0), "nodes"], nil)
               |> Jason.encode!()
               |> Imports.parse_file()
    end

    test "rejects locale codes that could escape an export directory" do
      data = minimal_import_data()
      data = put_in(data, ["localization"], %{"source_language" => "../../secrets", "languages" => []})

      assert {:error, {:invalid_locale_codes, ["../../secrets"]}} =
               data |> Jason.encode!() |> Imports.parse_file()
    end

    test "rejects dialogue responses without a stable response id" do
      data =
        minimal_import_data([
          dialogue_import_node("welcome", [%{"text" => "Continue"}])
        ])

      assert {:error, {:invalid_dialogue_ids, errors}} =
               data |> Jason.encode!() |> Imports.parse_file()

      assert Enum.any?(errors, &(&1.field == "response.id"))
    end

    test "rejects duplicate dialogue localization ids" do
      data =
        minimal_import_data([
          dialogue_import_node("shared_dialogue", []),
          dialogue_import_node("shared_dialogue", [])
        ])

      assert {:error, {:invalid_dialogue_ids, errors}} =
               data |> Jason.encode!() |> Imports.parse_file()

      assert Enum.any?(errors, &(&1.reason == "duplicate" and &1.value == "shared_dialogue"))
    end

    test "rejects malformed nested localization values without crashing" do
      data =
        put_in(minimal_import_data(), ["localization"], %{
          "languages" => ["es"],
          "strings" => [%{"translations" => ["not", "a", "map"]}],
          "glossary" => []
        })

      assert {:error, {:invalid_field_types, fields}} =
               data |> Jason.encode!() |> Imports.parse_file()

      assert "localization.languages[0]" in fields
      assert "localization.strings[0].translations" in fields
    end

    test "rejects malformed dialogue data without crashing" do
      data =
        minimal_import_data([
          %{"id" => Ecto.UUID.generate(), "type" => "dialogue", "data" => "invalid"}
        ])

      assert {:error, {:invalid_field_types, [field]}} =
               data |> Jason.encode!() |> Imports.parse_file()

      assert field == "flows[0].nodes[0].data"
    end

    test "rejects malformed translation payloads without crashing" do
      data =
        put_in(minimal_import_data(), ["localization"], %{
          "languages" => [],
          "strings" => [%{"translations" => %{"es" => "not-a-translation-object"}}],
          "glossary" => [%{"translations" => %{"es" => %{"invalid" => true}}}]
        })

      assert {:error, {:invalid_field_types, fields}} =
               data |> Jason.encode!() |> Imports.parse_file()

      assert "localization.strings[0].translations.es" in fields
      assert "localization.glossary[0].translations.es" in fields
    end
  end

  # =============================================================================
  # Entity count validation
  # =============================================================================

  describe "execute — entity count validation" do
    setup [:setup_projects]

    test "rejects malformed nested structures even when parse is bypassed", %{target: target} do
      data = put_in(minimal_import_data(), ["flows"], [%{"nodes" => ["invalid"]}])

      assert {:error, {:invalid_field_types, fields}} = Imports.execute(target, storyarn_plan(data))
      assert "flows[0].nodes[0]" in fields
    end

    test "rejects import with too many sheets", %{target: target} do
      # Build data that exceeds the sheets limit (1000)
      sheets = Enum.map(1..1001, fn i -> %{"id" => i, "name" => "Sheet #{i}"} end)

      data = %{
        "storyarn_version" => "1.0.0",
        "export_version" => "1.0.0",
        "project" => %{},
        "sheets" => sheets,
        "flows" => [],
        "scenes" => [],
        "screenplays" => []
      }

      assert {:error, {:entity_limits_exceeded, details}} = Imports.execute(target, storyarn_plan(data))
      assert Map.has_key?(details, :sheets)
      assert details.sheets.count == 1001
      assert details.sheets.limit == 1000
    end

    test "counts every inserted node when source IDs are duplicated", %{target: target} do
      source_id = Ecto.UUID.generate()

      nodes = [
        %{
          "id" => source_id,
          "type" => "annotation",
          "source" => "manual",
          "data" => %{"text" => "First"}
        },
        %{
          "id" => source_id,
          "type" => "annotation",
          "source" => "manual",
          "data" => %{"text" => "Second"}
        }
      ]

      data = put_in(minimal_import_data(nodes), ["flows", Access.at(0), "name"], "Imported flow")

      assert {:ok, result} = Imports.execute(target, storyarn_plan(data))
      assert result.counts.nodes == 2

      assert [flow] = result.flows
      assert flow.id |> Flows.list_nodes() |> length() == 2
    end
  end

  # =============================================================================
  # Preview
  # =============================================================================

  describe "preview" do
    setup [:setup_projects, :setup_with_data]

    test "returns entity counts", %{target: target, parsed: parsed} do
      {:ok, preview} = Imports.preview(target.id, parsed)

      assert preview.counts.sheets == 1
      assert preview.counts.flows == 1
      assert preview.counts.scenes == 1
      assert preview.counts.screenplays == 1
    end

    test "returns node counts in preview", %{target: target, parsed: parsed} do
      {:ok, preview} = Imports.preview(target.id, parsed)
      # 1 auto-created entry node + 1 dialogue = 2
      assert preview.counts.nodes >= 2
    end

    test "detects no conflicts in empty target", %{target: target, parsed: parsed} do
      {:ok, preview} = Imports.preview(target.id, parsed)
      assert preview.has_conflicts == false
      assert preview.conflicts == %{}
    end

    test "detects shortcut conflicts", %{source: source, target: target} do
      # Create conflicting entities in target
      sheet_fixture(target, %{name: "Hero"})
      flow_fixture(target, %{name: "Main Story"})
      scene_fixture(target, %{name: "World Map"})
      screenplay_fixture(target, %{name: "Act 1"})

      # Get shortcuts from source
      {:ok, source_json} =
        Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

      {:ok, source_parsed} = Imports.parse_file(source_json)

      {:ok, preview} = Imports.preview(target.id, source_parsed)
      assert preview.has_conflicts == true
      # Should detect conflicts in at least some schemas
      assert map_size(preview.conflicts) > 0
    end
  end

  # =============================================================================
  # Conflict Resolution: :skip
  # =============================================================================

  describe "conflict resolution — skip" do
    setup [:setup_projects, :setup_with_data]

    test "skips entities with conflicting shortcuts", %{target: target, parsed: parsed} do
      # Create a conflicting sheet in target
      existing = sheet_fixture(target, %{name: "Hero"})

      # Import with skip strategy
      {:ok, result} = Imports.execute(target, parsed, conflict_strategy: :skip)

      assert result.counts.sheets == 0
      assert result.counts.flows == 1
      assert result.counts.nodes >= 2

      # Should still have only one "Hero" sheet (the original)
      sheets = Storyarn.Sheets.list_all_sheets(target.id)
      hero_sheets = Enum.filter(sheets, &(&1.name == "Hero"))
      assert length(hero_sheets) == 1
      assert hd(hero_sheets).id == existing.id
    end
  end

  # =============================================================================
  # Conflict Resolution: :rename
  # =============================================================================

  describe "conflict resolution — rename" do
    setup [:setup_projects, :setup_with_data]

    test "renames conflicting shortcuts with suffix", %{target: target, parsed: parsed} do
      # Create a conflicting sheet in target
      sheet_fixture(target, %{name: "Hero"})

      # Import with rename strategy
      {:ok, _result} = Imports.execute(target, parsed, conflict_strategy: :rename)

      # Should now have two "Hero" sheets, one with modified shortcut
      sheets = Storyarn.Sheets.list_all_sheets(target.id)
      hero_sheets = Enum.filter(sheets, &String.starts_with?(&1.name, "Hero"))
      assert length(hero_sheets) == 2

      shortcuts = hero_sheets |> Enum.map(& &1.shortcut) |> Enum.sort()
      # One original, one with suffix
      assert Enum.any?(shortcuts, &String.contains?(&1, "-"))
    end
  end

  # =============================================================================
  # Conflict Resolution: :overwrite
  # =============================================================================

  describe "conflict resolution — overwrite" do
    setup [:setup_projects, :setup_with_data]

    test "soft-deletes existing entities and imports new ones", %{target: target, parsed: parsed} do
      # Create a conflicting sheet in target
      existing = sheet_fixture(target, %{name: "Hero"})

      # Import with overwrite strategy
      {:ok, _result} = Imports.execute(target, parsed, conflict_strategy: :overwrite)

      # The existing sheet should be soft-deleted
      reloaded = Storyarn.Repo.get(Storyarn.Sheets.Sheet, existing.id)
      assert reloaded.deleted_at

      # Should have a new active "Hero" sheet
      active_sheets = Storyarn.Sheets.list_all_sheets(target.id)
      hero_sheets = Enum.filter(active_sheets, &(&1.name == "Hero"))
      assert length(hero_sheets) == 1
      assert hd(hero_sheets).id != existing.id
    end
  end

  # =============================================================================
  # Import execution
  # =============================================================================

  describe "execute" do
    setup [:setup_projects, :setup_with_data]

    test "imports all entity types", %{target: target, parsed: parsed} do
      :ok = Collaboration.subscribe_dashboard(target.id)
      {:ok, result} = Imports.execute(target, parsed)

      assert result.sheets != []
      assert result.flows != []
      assert result.scenes != []
      assert result.screenplays != []
      assert_received {:dashboard_invalidate, :all}
    end

    test "preserves sheet blocks", %{target: target, parsed: parsed} do
      {:ok, _result} = Imports.execute(target, parsed)

      sheets = Storyarn.Sheets.list_all_sheets(target.id)
      hero = Enum.find(sheets, &(&1.name == "Hero"))
      assert hero

      hero_with_blocks = Storyarn.Repo.preload(hero, :blocks)
      assert hero_with_blocks.blocks != []
      assert Enum.find(hero_with_blocks.blocks, &(&1.type == "text")).word_count == 1
    end

    test "preserves flow nodes and connections", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed)

      flow = hd(result.flows)
      flow_with_data = Storyarn.Repo.preload(flow, [:nodes, :connections])

      # At least entry + dialogue nodes
      assert Enum.count(flow_with_data.nodes) >= 2
      assert Enum.find(flow_with_data.nodes, &(&1.type == "dialogue")).word_count == 1
    end

    test "preserves scene sub-entities", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed)

      scene = hd(result.scenes)
      scene_with_data = Storyarn.Repo.preload(scene, [:pins, :layers])

      assert scene_with_data.pins != []
    end

    test "preserves screenplay elements", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed)

      sp = hd(result.screenplays)
      sp_with_data = Storyarn.Repo.preload(sp, :elements)

      assert sp_with_data.elements != []
    end

    test "normalizes legacy Hub marker colors while importing", %{target: target} do
      data =
        minimal_import_data()
        |> Map.put("flows", [])
        |> Map.put("screenplays", [
          %{
            "id" => "legacy-screenplay",
            "name" => "Legacy Hub Colors",
            "position" => 0,
            "elements" => [
              %{
                "id" => "legacy-hub-marker",
                "type" => "hub_marker",
                "position" => 0,
                "data" => %{"hub_node_id" => "checkpoint", "color" => "blue"}
              }
            ]
          }
        ])

      assert {:ok, result} = Imports.execute(target, storyarn_plan(data))

      [screenplay] = result.screenplays
      [marker] = screenplay |> Storyarn.Repo.preload(:elements) |> Map.fetch!(:elements)
      assert marker.data["color"] == "#3b82f6"
    end

    test "remaps localized sheet names to the imported sheet ID", %{source: source, target: target} do
      source_language_fixture(source, %{locale_code: "en", name: "English"})
      language_fixture(source, %{locale_code: "es", name: "Spanish"})
      sheet = sheet_fixture(source, %{name: "Localized Hero"})
      [text] = Localization.get_texts_for_source("sheet", sheet.id)
      assert {:ok, _text} = Localization.update_text(text, %{translated_text: "Héroe", status: "final"})

      assert {:ok, json} =
               Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

      assert {:ok, parsed} = Imports.parse_file(json)
      assert {:ok, _result} = Imports.execute(target, parsed)

      imported_sheet = Enum.find(Storyarn.Sheets.list_all_sheets(target.id), &(&1.name == "Localized Hero"))
      refute imported_sheet.id == sheet.id

      assert [%{translated_text: "Héroe", status: "final"}] =
               Localization.get_texts_for_source("sheet", imported_sheet.id)
    end

    test "round-trips archived languages and their translations", %{source: source, target: target} do
      flow = flow_fixture(source, %{name: "Archived locale flow"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Remember me", "responses" => []}})
      source_language_fixture(source, %{locale_code: "en", name: "English"})
      spanish = language_fixture(source, %{locale_code: "es", name: "Spanish"})

      [text] = Localization.get_texts_for_source("flow_node", node.id)
      assert {:ok, _text} = Localization.update_text(text, %{translated_text: "Recuérdame", status: "final"})
      assert {:ok, archived_language} = Localization.remove_language(spanish)

      assert {:ok, json} =
               Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

      assert {:ok, parsed} = Imports.parse_file(json)
      assert {:ok, result} = Imports.execute(target, parsed)

      imported_language =
        target.id
        |> Localization.list_languages_for_backup()
        |> Enum.find(&(&1.locale_code == "es"))

      assert imported_language.archived_at == archived_language.archived_at

      imported_flow = Enum.find(result.flows, &(&1.name == "Archived locale flow"))
      imported_node = imported_flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "dialogue"))

      assert [%{translated_text: "Recuérdame", status: "final"}] =
               Localization.get_texts_for_source("flow_node", imported_node.id)
    end

    test "rekeys an imported dialogue that collides without losing its translation", %{
      source: source,
      target: target
    } do
      source_language_fixture(source, %{locale_code: "en", name: "English"})
      language_fixture(source, %{locale_code: "es", name: "Spanish"})

      source_flow = flow_fixture(source, %{name: "Collision Source"})

      source_node =
        node_fixture(source_flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "shared_import_dialogue",
            "text" => "Imported line",
            "responses" => []
          }
        })

      [source_text] = Localization.get_texts_for_source("flow_node", source_node.id)
      assert {:ok, _text} = Localization.update_text(source_text, %{translated_text: "Línea importada", status: "final"})

      target_flow = flow_fixture(target, %{name: "Existing Target"})

      existing_node =
        node_fixture(target_flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "shared_import_dialogue",
            "text" => "Existing line",
            "responses" => []
          }
        })

      assert {:ok, json} =
               Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

      assert {:ok, parsed} = Imports.parse_file(json)
      assert {:ok, result} = Imports.execute(target, parsed, conflict_strategy: :rename)

      imported_flow = Enum.find(result.flows, &(&1.name == "Collision Source"))
      imported_node = imported_flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "dialogue"))

      refute imported_node.data["localization_id"] == existing_node.data["localization_id"]

      assert [%{translated_text: "Línea importada", status: "final"}] =
               Localization.get_texts_for_source("flow_node", imported_node.id)
    end

    test "rekeys a dialogue that collides with a deleted target node", %{
      source: source,
      target: target
    } do
      source_flow = flow_fixture(source, %{name: "Deleted Collision Source"})

      _source_node =
        node_fixture(source_flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "deleted_target_dialogue",
            "text" => "Imported line",
            "responses" => []
          }
        })

      target_flow = flow_fixture(target, %{name: "Deleted Target"})

      existing_node =
        node_fixture(target_flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "deleted_target_dialogue",
            "text" => "Deleted line",
            "responses" => []
          }
        })

      assert {:ok, deleted_node, _meta} = Flows.delete_node(existing_node)
      assert deleted_node.deleted_at

      assert {:ok, json} =
               Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

      assert {:ok, parsed} = Imports.parse_file(json)
      assert {:ok, result} = Imports.execute(target, parsed, conflict_strategy: :rename)

      imported_flow = Enum.find(result.flows, &(&1.name == "Deleted Collision Source"))
      imported_node = imported_flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "dialogue"))

      refute imported_node.data["localization_id"] == deleted_node.data["localization_id"]
    end

    test "remaps node flow references after all flows are imported", %{source: source, target: target} do
      referenced_flow = flow_fixture(source, %{name: "Referenced Flow"})
      source_flow = flow_fixture(source, %{name: "Source Flow"})

      _subflow =
        node_fixture(source_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      _exit =
        node_fixture(source_flow, %{
          type: "exit",
          data: %{"target_type" => "flow", "target_id" => referenced_flow.id}
        })

      {:ok, json} =
        Exports.export_project(source, %{format: :storyarn, validate_before_export: false})

      {:ok, parsed} = Imports.parse_file(json)
      {:ok, _result} = Imports.execute(target, parsed)

      imported_flows = Flows.list_flows(target.id)
      imported_referenced_flow = Enum.find(imported_flows, &(&1.name == "Referenced Flow"))
      imported_source_flow = Enum.find(imported_flows, &(&1.name == "Source Flow"))
      imported_nodes = Flows.list_nodes(imported_source_flow.id)

      imported_subflow = Enum.find(imported_nodes, &(&1.type == "subflow"))
      imported_exit = Enum.find(imported_nodes, &(&1.data["target_type"] == "flow"))

      assert imported_subflow.data["referenced_flow_id"] == imported_referenced_flow.id
      assert imported_exit.data["target_id"] == imported_referenced_flow.id
    end
  end

  defp minimal_import_data(nodes \\ []) do
    %{
      "storyarn_version" => "1.0.0",
      "export_version" => "1.0.0",
      "project" => %{},
      "sheets" => [],
      "flows" => [%{"id" => "flow-1", "nodes" => nodes}],
      "scenes" => [],
      "screenplays" => []
    }
  end

  defp dialogue_import_node(localization_id, responses) do
    %{
      "id" => Ecto.UUID.generate(),
      "type" => "dialogue",
      "data" => %{"localization_id" => localization_id, "text" => "Hello", "responses" => responses}
    }
  end
end
