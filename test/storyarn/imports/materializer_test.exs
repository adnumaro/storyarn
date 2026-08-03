defmodule Storyarn.Imports.MaterializerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Imports
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.Materializer
  alias Storyarn.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Localization
  alias Storyarn.References.EntityReference
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet

  # =============================================================================
  # Setup
  # =============================================================================

  defp setup_projects(_context) do
    user = user_fixture()
    source = project_fixture(user)
    target = project_fixture(user)
    %{user: user, source: source, target: target}
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

    Map.merge(context, %{
      parsed: import_plan(project_plan_data(source)),
      sheet: sheet,
      flow: flow,
      scene: scene
    })
  end

  # =============================================================================
  # Plan validation
  # =============================================================================

  describe "validate_plan_data" do
    test "returns error for missing required keys" do
      assert {:error, {:missing_required_keys, missing}} = Materializer.validate_plan_data(%{"foo" => "bar"})
      assert "storyarn_version" in missing
      assert "export_version" in missing
      assert "project" in missing
    end

    test "accepts explicit null flow collections without crashing" do
      assert :ok =
               minimal_import_data()
               |> Map.put("flows", nil)
               |> Materializer.validate_plan_data()

      assert :ok =
               minimal_import_data()
               |> put_in(["flows", Access.at(0), "nodes"], nil)
               |> Materializer.validate_plan_data()
    end

    test "rejects locale codes that could escape an export directory" do
      data = minimal_import_data()
      data = put_in(data, ["localization"], %{"source_language" => "../../secrets", "languages" => []})

      assert {:error, {:invalid_locale_codes, ["../../secrets"]}} = Materializer.validate_plan_data(data)
    end

    test "rejects dialogue responses without a stable response id" do
      data =
        minimal_import_data([
          dialogue_import_node("welcome", [%{"text" => "Continue"}])
        ])

      assert {:error, {:invalid_dialogue_ids, errors}} = Materializer.validate_plan_data(data)

      assert Enum.any?(errors, &(&1.field == "response.id"))
    end

    test "rejects duplicate dialogue localization ids" do
      data =
        minimal_import_data([
          dialogue_import_node("shared_dialogue", []),
          dialogue_import_node("shared_dialogue", [])
        ])

      assert {:error, {:invalid_dialogue_ids, errors}} = Materializer.validate_plan_data(data)

      assert Enum.any?(errors, &(&1.reason == "duplicate" and &1.value == "shared_dialogue"))
    end

    test "rejects malformed nested localization values without crashing" do
      data =
        put_in(minimal_import_data(), ["localization"], %{
          "languages" => ["es"],
          "strings" => [%{"translations" => ["not", "a", "map"]}],
          "glossary" => []
        })

      assert {:error, {:invalid_field_types, fields}} = Materializer.validate_plan_data(data)

      assert "localization.languages[0]" in fields
      assert "localization.strings[0].translations" in fields
    end

    test "rejects malformed dialogue data without crashing" do
      data =
        minimal_import_data([
          %{"id" => Ecto.UUID.generate(), "type" => "dialogue", "data" => "invalid"}
        ])

      assert {:error, {:invalid_field_types, [field]}} = Materializer.validate_plan_data(data)

      assert field == "flows[0].nodes[0].data"
    end

    test "rejects malformed sequence config without crashing" do
      data =
        minimal_import_data([
          %{
            "id" => Ecto.UUID.generate(),
            "type" => "sequence",
            "data" => %{},
            "sequence_config" => "invalid"
          }
        ])

      assert {:error, {:invalid_field_types, [field]}} = Materializer.validate_plan_data(data)

      assert field == "flows[0].nodes[0].sequence_config"
    end

    test "rejects a sequence without its required config" do
      data =
        minimal_import_data([
          %{
            "id" => Ecto.UUID.generate(),
            "type" => "sequence",
            "data" => %{}
          }
        ])

      assert {:error, {:invalid_field_types, [field]}} = Materializer.validate_plan_data(data)

      assert field == "flows[0].nodes[0].sequence_config"
    end

    test "rejects a sequence config without its required name" do
      data =
        minimal_import_data([
          %{
            "id" => Ecto.UUID.generate(),
            "type" => "sequence",
            "data" => %{},
            "sequence_config" => %{}
          }
        ])

      assert {:error, {:invalid_field_types, [field]}} = Materializer.validate_plan_data(data)

      assert field == "flows[0].nodes[0].sequence_config"
    end

    test "rejects malformed translation payloads without crashing" do
      data =
        put_in(minimal_import_data(), ["localization"], %{
          "languages" => [],
          "strings" => [%{"translations" => %{"es" => "not-a-translation-object"}}],
          "glossary" => [%{"translations" => %{"es" => %{"invalid" => true}}}]
        })

      assert {:error, {:invalid_field_types, fields}} = Materializer.validate_plan_data(data)

      assert "localization.strings[0].translations.es" in fields
      assert "localization.glossary[0].translations.es" in fields
    end
  end

  # =============================================================================
  # Entity count validation
  # =============================================================================

  describe "execute — entity count validation" do
    setup [:setup_projects]

    test "rejects malformed nested structures when a plan reaches execution", %{target: target} do
      data = put_in(minimal_import_data(), ["flows"], [%{"nodes" => ["invalid"]}])

      assert {:error, {:invalid_field_types, fields}} = Imports.execute(target, import_plan(data))
      assert "flows[0].nodes[0]" in fields
    end

    test "rejects import with too many sheets", %{target: target} do
      # Build data that exceeds the sheets limit (1000)
      sheets = Enum.map(1..1001, fn i -> %{"id" => i, "name" => "Sheet #{i}"} end)

      data = plan_data(%{"sheets" => sheets})

      assert {:error, {:entity_limits_exceeded, details}} = Imports.execute(target, import_plan(data))
      assert Map.has_key?(details, :sheets)
      assert details.sheets.count == 1001
      assert details.sheets.limit == 1000
    end

    test "rejects a stale project struct after the target enters trash", %{target: target} do
      target
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      assert {:error, :project_not_active} =
               Imports.execute(target, import_plan(minimal_import_data()))
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

      assert {:ok, result} = Imports.execute(target, import_plan(data))
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

    test "detects shortcut conflicts", %{target: target, parsed: parsed} do
      # Create conflicting entities in target
      sheet_fixture(target, %{name: "Hero"})
      flow_fixture(target, %{name: "Main Story"})
      scene_fixture(target, %{name: "World Map"})

      {:ok, preview} = Imports.preview(target.id, parsed)
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
      sheets = Sheets.list_all_sheets(target.id)
      hero_sheets = Enum.filter(sheets, &(&1.name == "Hero"))
      assert length(hero_sheets) == 1
      assert hd(hero_sheets).id == existing.id
    end
  end

  describe "re-importing rewrites references to renamed sheets" do
    setup [:setup_projects]

    test "a suffixed variables sheet drags every imported reference with it", %{target: target} do
      # Importing the same file twice suffixes the second `yarn` sheet to
      # `yarn-2`. Conditions, assignments and text interpolations in the second
      # import's nodes must follow the rename, or they silently read the first
      # import's sheet.
      source = """
      title: Start
      ---
      <<declare $gold = 10>>
      Guide: You have {$gold} coins.
      <<if $gold >= 5>>
          Guide: Rich enough.
      <<endif>>
      <<set $gold to 5>>
      ===
      """

      import_once = fn ->
        assert {:ok, plan} = Imports.parse_file("wallet.yarn", source)

        assert {:ok, resolved} =
                 ReviewDecisions.apply(plan, true, [%{"speaker" => "Guide", "action" => "create_sheet"}])

        Imports.execute(target, resolved, conflict_strategy: :rename)
      end

      assert {:ok, _first} = import_once.()

      # ENG-73: the importer claims is_main positionally, so a second import
      # collides with the first one's main flow before reaching the sheets.
      # Clear it here — that behaviour ships separately.
      Repo.update_all(Storyarn.Flows.Flow, set: [is_main: false])

      assert {:ok, _second} = import_once.()

      sheets = Sheets.list_all_sheets(target.id)
      assert Enum.any?(sheets, &(&1.shortcut == "yarn"))
      assert Enum.any?(sheets, &(&1.shortcut == "yarn-2"))

      flows = Flows.list_flows(target.id)
      second_flow = Enum.find(flows, &(&1.shortcut == "start-2"))
      assert second_flow

      nodes = Flows.list_nodes(second_flow.id)

      condition = Enum.find(nodes, &(&1.type == "condition"))
      [rule] = condition.data["condition"]["blocks"] |> hd() |> Map.fetch!("rules")
      assert rule["sheet"] == "yarn-2"
      assert rule["variable"] == "gold"

      instruction = Enum.find(nodes, &(&1.type == "instruction"))
      [assignment] = instruction.data["assignments"]
      assert assignment["sheet"] == "yarn-2"
      assert assignment["variable"] == "gold"

      dialogue_texts =
        for node <- nodes, node.type == "dialogue", is_binary(node.data["text"]), do: node.data["text"]

      assert Enum.any?(dialogue_texts, &String.contains?(&1, "{yarn-2.gold}"))
      refute Enum.any?(dialogue_texts, &String.contains?(&1, "{yarn.gold}"))

      # The first import is untouched.
      first_flow = Enum.find(flows, &(&1.shortcut == "start"))
      first_nodes = Flows.list_nodes(first_flow.id)
      first_condition = Enum.find(first_nodes, &(&1.type == "condition"))
      [first_rule] = first_condition.data["condition"]["blocks"] |> hd() |> Map.fetch!("rules")
      assert first_rule["sheet"] == "yarn"
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
      sheets = Sheets.list_all_sheets(target.id)
      hero_sheets = Enum.filter(sheets, &String.starts_with?(&1.name, "Hero"))
      assert length(hero_sheets) == 2

      shortcuts = hero_sheets |> Enum.map(& &1.shortcut) |> Enum.sort()
      # One original, one with suffix
      assert Enum.any?(shortcuts, &String.contains?(&1, "-"))
    end

    test "keeps renamed shortcuts within the persisted limit", %{target: target, parsed: parsed} do
      shortcut = String.duplicate("a", 50)
      sheet_fixture(target, %{name: "Existing Long Shortcut", shortcut: shortcut})

      data = put_in(parsed.data, ["sheets", Access.at(0), "shortcut"], shortcut)
      parsed = %{parsed | data: data}

      assert {:ok, result} =
               Imports.execute(target, parsed, conflict_strategy: :rename)

      [imported_sheet] = result.sheets
      assert String.length(imported_sheet.shortcut) <= 50
      assert String.ends_with?(imported_sheet.shortcut, "-2")
    end

    test "reserves generated shortcuts across every entity in the same import", %{
      target: target,
      parsed: parsed
    } do
      sheet_fixture(target, %{name: "Existing", shortcut: "character"})
      [source_sheet] = parsed.data["sheets"]

      first =
        source_sheet
        |> Map.put("id", "first-character")
        |> Map.put("name", "First character")
        |> Map.put("shortcut", "character")

      second =
        source_sheet
        |> Map.put("id", "second-character")
        |> Map.put("name", "Second character")
        |> Map.put("shortcut", "character-2")

      parsed = %{parsed | data: Map.put(parsed.data, "sheets", [first, second])}

      assert {:ok, result} = Imports.execute(target, parsed, conflict_strategy: :rename)

      assert result.sheets
             |> Enum.map(& &1.shortcut)
             |> Enum.sort() == ["character-2", "character-2-2"]
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
      reloaded = Repo.get(Sheet, existing.id)
      assert reloaded.deleted_at

      # Should have a new active "Hero" sheet
      active_sheets = Sheets.list_all_sheets(target.id)
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
      assert_received {:dashboard_invalidate, :all}
    end

    test "preserves sheet blocks", %{target: target, parsed: parsed} do
      {:ok, _result} = Imports.execute(target, parsed)

      sheets = Sheets.list_all_sheets(target.id)
      hero = Enum.find(sheets, &(&1.name == "Hero"))
      assert hero

      hero_with_blocks = Repo.preload(hero, :blocks)
      assert hero_with_blocks.blocks != []
      assert Enum.find(hero_with_blocks.blocks, &(&1.type == "text")).word_count == 1
    end

    test "preserves flow nodes and connections", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed)

      flow = hd(result.flows)
      flow_with_data = Repo.preload(flow, [:nodes, :connections])

      # At least entry + dialogue nodes
      assert Enum.count(flow_with_data.nodes) >= 2
      assert Enum.find(flow_with_data.nodes, &(&1.type == "dialogue")).word_count == 1
    end

    test "round-trips sequence config and nested node hierarchy", %{
      source: source,
      target: target
    } do
      flow = flow_fixture(source, %{name: "Sequence fidelity"})

      assert {:ok, sequence} =
               Flows.create_sequence(flow.id, %{
                 "name" => "Act I",
                 "width" => 640.0,
                 "height" => 360.0,
                 "position_x" => 120.0,
                 "position_y" => 80.0
               })

      _nested_node =
        node_fixture(flow, %{
          type: "annotation",
          parent_id: sequence.id,
          data: %{"text" => "Nested in Act I"}
        })

      assert {:ok, result} = Imports.execute(target, import_plan(project_plan_data(source)))

      imported_flow = Enum.find(result.flows, &(&1.name == "Sequence fidelity"))
      imported_nodes = Flows.list_nodes(imported_flow.id)
      imported_sequence = Enum.find(imported_nodes, &(&1.type == "sequence"))
      imported_nested_node = Enum.find(imported_nodes, &(&1.data["text"] == "Nested in Act I"))
      imported_sequence = Flows.get_sequence!(imported_flow.id, imported_sequence.id)

      imported_config =
        case imported_sequence.sequence_config do
          nil -> nil
          config -> Map.take(config, [:name, :width, :height])
        end

      assert %{
               config: %{
                 name: "Act I",
                 width: 640.0,
                 height: 360.0
               },
               nested_parent_id: imported_sequence.id
             } == %{
               config: imported_config,
               nested_parent_id: imported_nested_node.parent_id
             }
    end

    test "rebuilds flow-node entity and variable references after import", %{
      source: source,
      target: target
    } do
      character =
        sheet_fixture(source, %{
          name: "Reference target",
          shortcut: "characters.reference-target"
        })

      health =
        block_fixture(character, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      flow = flow_fixture(source, %{name: "Reference fidelity"})

      assert {:ok, _dialogue} =
               Flows.create_node(flow, %{
                 type: "dialogue",
                 data: %{
                   "speaker_sheet_id" => character.id,
                   "text" => "Referenced dialogue",
                   "responses" => []
                 }
               })

      assert {:ok, _instruction} =
               Flows.create_node(flow, %{
                 type: "instruction",
                 data: %{
                   "assignments" => [
                     %{
                       "id" => Ecto.UUID.generate(),
                       "sheet" => character.shortcut,
                       "variable" => health.variable_name,
                       "operator" => "set",
                       "value" => "100",
                       "value_type" => "literal"
                     }
                   ]
                 }
               })

      assert {:ok, result} = Imports.execute(target, import_plan(project_plan_data(source)))

      imported_sheet = Enum.find(result.sheets, &(&1.name == character.name))
      imported_sheet = Repo.preload(imported_sheet, :blocks)
      imported_health = Enum.find(imported_sheet.blocks, &(&1.variable_name == health.variable_name))
      imported_flow = Enum.find(result.flows, &(&1.name == flow.name))
      imported_nodes = Flows.list_nodes(imported_flow.id)
      imported_dialogue = Enum.find(imported_nodes, &(&1.type == "dialogue"))
      imported_instruction = Enum.find(imported_nodes, &(&1.type == "instruction"))

      assert %EntityReference{} =
               Repo.get_by(EntityReference,
                 source_type: "flow_node",
                 source_id: imported_dialogue.id,
                 target_type: "sheet",
                 target_id: imported_sheet.id,
                 context: "speaker"
               )

      assert %VariableReference{} =
               Repo.get_by(VariableReference,
                 source_type: "flow_node",
                 source_id: imported_instruction.id,
                 block_id: imported_health.id,
                 kind: "write"
               )
    end

    test "preserves scene sub-entities", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed)

      scene = hd(result.scenes)
      scene_with_data = Repo.preload(scene, [:pins, :layers])

      assert scene_with_data.pins != []
    end

    test "normalizes legacy Flow Hub colors while importing", %{target: target} do
      data =
        [
          %{
            "id" => "legacy-hub",
            "type" => "hub",
            "data" => %{"hub_id" => "checkpoint", "color" => "blue"}
          }
        ]
        |> minimal_import_data()
        |> put_in(["flows", Access.at(0), "name"], "Legacy Hub Colors")

      assert {:ok, result} = Imports.execute(target, import_plan(data))

      flow = Enum.find(result.flows, &(&1.name == "Legacy Hub Colors"))
      hub = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "hub"))
      assert hub.data["color"] == "#3b82f6"
    end

    test "remaps localized sheet names to the imported sheet ID", %{source: source, target: target} do
      source_language_fixture(source, %{locale_code: "en", name: "English"})
      language_fixture(source, %{locale_code: "es", name: "Spanish"})
      sheet = sheet_fixture(source, %{name: "Localized Hero"})
      [text] = Localization.get_texts_for_source("sheet", sheet.id)
      assert {:ok, _text} = Localization.update_text(text, %{translated_text: "Héroe", status: "final"})

      assert {:ok, _result} = Imports.execute(target, import_plan(project_plan_data(source)))

      imported_sheet = Enum.find(Sheets.list_all_sheets(target.id), &(&1.name == "Localized Hero"))
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

      assert {:ok, result} = Imports.execute(target, import_plan(project_plan_data(source)))

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

      assert {:ok, result} =
               Imports.execute(target, import_plan(project_plan_data(source)), conflict_strategy: :rename)

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

      assert {:ok, result} =
               Imports.execute(target, import_plan(project_plan_data(source)), conflict_strategy: :rename)

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

      {:ok, _result} = Imports.execute(target, import_plan(project_plan_data(source)))

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

  # =============================================================================
  # Import-plan fixtures
  #
  # Every parser normalizes its source into this one envelope — see
  # `Imports.Parsers.Yarn.Normalizer` — and the materializer never branches on
  # `plan.format`, so the scenarios above build the plan directly instead of
  # round-tripping through a serializer. The builders carry exactly the keys the
  # materializer reads back. Assets, table blocks, sheet avatars, glossary
  # entries and scene zones/connections/annotations have no fixture in this
  # file, so they are deliberately absent rather than emitted empty; add the
  # matching builder alongside any new fixture that needs them.
  # =============================================================================

  describe "main flow collision" do
    setup [:setup_projects]

    test "returns a clear error instead of raising when the project has a main flow", %{
      source: source,
      target: target
    } do
      flow_fixture(source, %{name: "Imported Main", is_main: true})
      flow_fixture(target, %{name: "Existing Main", is_main: true})

      plan = import_plan(project_plan_data(source))

      # `flows_project_id_is_main_index` had no matching `unique_constraint`, so
      # this raised `Ecto.ConstraintError` — a raw 500 with no usable message.
      assert {:error, :project_already_has_main_flow} =
               Imports.execute(target, plan, conflict_strategy: :rename)

      # The failure is permanent, so the worker must not spend three attempts on
      # a constraint violation that can only ever fail again.
      assert {"project_already_has_main_flow", _message, true} =
               Storyarn.Imports.Error.classify(:project_already_has_main_flow)

      main_flows = target.id |> Flows.list_flows() |> Enum.filter(& &1.is_main)
      assert [%{name: "Existing Main"}] = main_flows
    end
  end

  defp import_plan(data) do
    %ImportPlan{
      format: :test,
      parser_version: "1",
      source_kind: :file,
      data: data
    }
  end

  defp plan_data(sections) do
    Map.merge(
      %{
        "storyarn_version" => "1.0.0",
        "export_version" => "1.0.0",
        "project" => %{},
        "sheets" => [],
        "flows" => [],
        "scenes" => []
      },
      sections
    )
  end

  defp minimal_import_data(nodes \\ []) do
    plan_data(%{"flows" => [%{"id" => "flow-1", "nodes" => nodes}]})
  end

  defp dialogue_import_node(localization_id, responses) do
    %{
      "id" => Ecto.UUID.generate(),
      "type" => "dialogue",
      "data" => %{"localization_id" => localization_id, "text" => "Hello", "responses" => responses}
    }
  end

  defp project_plan_data(project) do
    plan_data(%{
      "project" => %{"id" => to_string(project.id), "name" => project.name},
      "sheets" => project.id |> Sheets.list_sheets_for_export() |> Enum.map(&sheet_entry/1),
      "scenes" => project.id |> Scenes.list_scenes_for_export() |> Enum.map(&scene_entry/1),
      "flows" => project.id |> Flows.list_flows_for_export() |> Enum.map(&flow_entry/1),
      "localization" => localization_entry(project.id)
    })
  end

  # -- Sheets --

  defp sheet_entry(sheet) do
    %{
      "id" => to_string(sheet.id),
      "shortcut" => sheet.shortcut,
      "name" => sheet.name,
      "description" => sheet.description,
      "color" => sheet.color,
      "parent_id" => optional_id(sheet.parent_id),
      "position" => sheet.position,
      "blocks" => Enum.map(sheet.blocks, &block_entry/1)
    }
  end

  defp block_entry(block) do
    %{
      "id" => to_string(block.id),
      "type" => block.type,
      "position" => block.position,
      "config" => block.config || %{},
      "value" => block.value || %{},
      "is_constant" => block.is_constant,
      "variable_name" => block.variable_name,
      "scope" => block.scope,
      "required" => block.required,
      "detached" => block.detached,
      "column_group_id" => block.column_group_id,
      "column_index" => block.column_index
    }
  end

  # -- Flows --

  defp flow_entry(flow) do
    %{
      "id" => to_string(flow.id),
      "shortcut" => flow.shortcut,
      "name" => flow.name,
      "description" => flow.description,
      "parent_id" => optional_id(flow.parent_id),
      "position" => flow.position,
      "is_main" => flow.is_main,
      "settings" => flow.settings || %{},
      "scene_id" => optional_id(flow.scene_id),
      "nodes" => Enum.map(flow.nodes, &node_entry/1),
      "connections" => Enum.map(flow.connections, &flow_connection_entry/1)
    }
  end

  defp node_entry(node) do
    entry = %{
      "id" => to_string(node.id),
      "type" => node.type,
      "position_x" => node.position_x,
      "position_y" => node.position_y,
      "parent_id" => optional_id(node.parent_id),
      "data" => node.data || %{}
    }

    case node.sequence_config do
      %{name: name, width: width, height: height} ->
        Map.put(entry, "sequence_config", %{"name" => name, "width" => width, "height" => height})

      _no_sequence_config ->
        entry
    end
  end

  defp flow_connection_entry(connection) do
    %{
      "id" => to_string(connection.id),
      "source_node_id" => to_string(connection.source_node_id),
      "source_pin" => connection.source_pin,
      "target_node_id" => to_string(connection.target_node_id),
      "target_pin" => connection.target_pin,
      "label" => connection.label
    }
  end

  # -- Scenes --

  defp scene_entry(scene) do
    %{
      "id" => to_string(scene.id),
      "shortcut" => scene.shortcut,
      "name" => scene.name,
      "description" => scene.description,
      "parent_id" => optional_id(scene.parent_id),
      "position" => scene.position,
      "width" => scene.width,
      "height" => scene.height,
      "default_zoom" => scene.default_zoom,
      "default_center_x" => scene.default_center_x,
      "default_center_y" => scene.default_center_y,
      "scale_unit" => scene.scale_unit,
      "scale_value" => scene.scale_value,
      "fog_color" => scene.fog_color,
      "fog_opacity" => scene.fog_opacity,
      "layers" => Enum.map(scene.layers, &layer_entry/1),
      "pins" => Enum.map(scene.pins, &pin_entry/1)
    }
  end

  defp layer_entry(layer) do
    %{
      "id" => to_string(layer.id),
      "name" => layer.name,
      "is_default" => layer.is_default,
      "position" => layer.position,
      "visible" => layer.visible,
      "fog_enabled" => layer.fog_enabled
    }
  end

  defp pin_entry(pin) do
    %{
      "id" => to_string(pin.id),
      "layer_id" => optional_id(pin.layer_id),
      "position_x" => pin.position_x,
      "position_y" => pin.position_y,
      "pin_type" => pin.pin_type,
      "icon" => pin.icon,
      "color" => pin.color,
      "opacity" => pin.opacity,
      "label" => pin.label,
      "shortcut" => pin.shortcut,
      "hidden" => pin.hidden,
      "flow_id" => optional_id(pin.flow_id),
      "tooltip" => pin.tooltip,
      "size" => pin.size,
      "position" => pin.position,
      "locked" => pin.locked,
      "sheet_id" => optional_id(pin.sheet_id),
      "condition" => pin.condition,
      "condition_effect" => pin.condition_effect,
      "is_playable" => pin.is_playable,
      "is_leader" => pin.is_leader
    }
  end

  # -- Localization --

  defp localization_entry(project_id) do
    languages = Localization.list_languages_for_backup(project_id)
    locale_codes = Enum.map(languages, & &1.locale_code)
    source_language = Enum.find(languages, & &1.is_source)

    %{
      "source_language" => (source_language && source_language.locale_code) || "en",
      "languages" => Enum.map(languages, &language_entry/1),
      "strings" => project_id |> Localization.list_texts_for_backup(locale_codes) |> string_entries()
    }
  end

  defp language_entry(language) do
    %{
      "locale_code" => language.locale_code,
      "name" => language.name,
      "is_source" => language.is_source,
      "position" => language.position,
      "archived_at" => optional_iso8601(language.archived_at)
    }
  end

  defp string_entries(texts) do
    texts
    |> Enum.group_by(&{&1.source_type, &1.source_id, &1.source_field})
    |> Enum.map(fn {{source_type, source_id, source_field}, locale_texts} ->
      first = List.first(locale_texts)

      %{
        "source_type" => source_type,
        "source_id" => to_string(source_id),
        "source_field" => source_field,
        "source_text" => first.source_text,
        "source_text_hash" => first.source_text_hash,
        "speaker_sheet_id" => optional_id(first.speaker_sheet_id),
        "translations" => Map.new(locale_texts, &{&1.locale_code, translation_entry(&1)})
      }
    end)
  end

  defp translation_entry(text) do
    %{
      "translated_text" => text.translated_text,
      "translated_source_hash" => text.translated_source_hash,
      "status" => text.status,
      "vo_status" => text.vo_status,
      "translator_notes" => text.translator_notes,
      "reviewer_notes" => text.reviewer_notes,
      "word_count" => text.word_count,
      "machine_translated" => text.machine_translated,
      "last_translated_at" => optional_iso8601(text.last_translated_at),
      "last_reviewed_at" => optional_iso8601(text.last_reviewed_at),
      "archived_at" => optional_iso8601(text.archived_at),
      "archive_reason" => text.archive_reason
    }
  end

  # -- Shared --

  defp optional_id(nil), do: nil
  defp optional_id(id), do: to_string(id)

  defp optional_iso8601(nil), do: nil
  defp optional_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
