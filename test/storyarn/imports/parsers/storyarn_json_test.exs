defmodule Storyarn.Imports.Parsers.StoryarnJSONTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports
  alias Storyarn.Imports

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ScreenplaysFixtures

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
  # Preview
  # =============================================================================

  describe "preview" do
    setup [:setup_projects, :setup_with_data]

    test "returns entity counts", %{target: target, parsed: parsed} do
      {:ok, preview} = Imports.preview(target.id, parsed.data)

      assert preview.counts.sheets == 1
      assert preview.counts.flows == 1
      assert preview.counts.scenes == 1
      assert preview.counts.screenplays == 1
    end

    test "returns node counts in preview", %{target: target, parsed: parsed} do
      {:ok, preview} = Imports.preview(target.id, parsed.data)
      # 1 auto-created entry node + 1 dialogue = 2
      assert preview.counts.nodes >= 2
    end

    test "detects no conflicts in empty target", %{target: target, parsed: parsed} do
      {:ok, preview} = Imports.preview(target.id, parsed.data)
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

      {:ok, preview} = Imports.preview(target.id, source_parsed.data)
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
      {:ok, _result} = Imports.execute(target, parsed.data, conflict_strategy: :skip)

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
      {:ok, _result} = Imports.execute(target, parsed.data, conflict_strategy: :rename)

      # Should now have two "Hero" sheets, one with modified shortcut
      sheets = Storyarn.Sheets.list_all_sheets(target.id)
      hero_sheets = Enum.filter(sheets, &String.starts_with?(&1.name, "Hero"))
      assert length(hero_sheets) == 2

      shortcuts = Enum.map(hero_sheets, & &1.shortcut) |> Enum.sort()
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
      {:ok, _result} = Imports.execute(target, parsed.data, conflict_strategy: :overwrite)

      # The existing sheet should be soft-deleted
      reloaded = Storyarn.Repo.get(Storyarn.Sheets.Sheet, existing.id)
      assert reloaded.deleted_at != nil

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
      {:ok, result} = Imports.execute(target, parsed.data)

      assert result.sheets != []
      assert result.flows != []
      assert result.scenes != []
      assert result.screenplays != []
    end

    test "preserves sheet blocks", %{target: target, parsed: parsed} do
      {:ok, _result} = Imports.execute(target, parsed.data)

      sheets = Storyarn.Sheets.list_all_sheets(target.id)
      hero = Enum.find(sheets, &(&1.name == "Hero"))
      assert hero != nil

      hero_with_blocks = Storyarn.Repo.preload(hero, :blocks)
      assert hero_with_blocks.blocks != []
    end

    test "preserves flow nodes and connections", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed.data)

      flow = hd(result.flows)
      flow_with_data = Storyarn.Repo.preload(flow, [:nodes, :connections])

      # At least entry + dialogue nodes
      assert Enum.count(flow_with_data.nodes) >= 2
    end

    test "preserves scene sub-entities", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed.data)

      scene = hd(result.scenes)
      scene_with_data = Storyarn.Repo.preload(scene, [:pins, :layers])

      assert scene_with_data.pins != []
    end

    test "preserves screenplay elements", %{target: target, parsed: parsed} do
      {:ok, result} = Imports.execute(target, parsed.data)

      sp = hd(result.screenplays)
      sp_with_data = Storyarn.Repo.preload(sp, :elements)

      assert sp_with_data.elements != []
    end
  end
end
