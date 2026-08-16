defmodule Storyarn.Versioning.SnapshotProjectContentHealthTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotProjectContentHealth

  @project_id 900

  test "locates every member of a project tree cycle without changing the captured parents" do
    snapshot =
      project_snapshot(
        sheets: [sheet_entry(11, "first"), sheet_entry(12, "second")],
        tree_sheets: [tree_entry(11, 12), tree_entry(12, 11)]
      )

    assert SnapshotProjectContentHealth.issues(snapshot, @project_id) == [
             expected_issue(:project_snapshot_tree_cycle, :sheet, 11, "parent_id"),
             expected_issue(:project_snapshot_tree_cycle, :sheet, 12, "parent_id")
           ]

    assert get_in(snapshot, ["tree", "sheets"]) == [tree_entry(11, 12), tree_entry(12, 11)]
  end

  test "reports invalid parents and every missing or orphan tree identity" do
    snapshot =
      project_snapshot(
        sheets: [sheet_entry(11, "first"), sheet_entry(12, "second")],
        tree_sheets: [tree_entry(11, 99), tree_entry(13, nil)]
      )

    assert SnapshotProjectContentHealth.issues(snapshot, @project_id) == [
             expected_issue(:invalid_project_snapshot_tree_parent, :sheet, 11, "parent_id"),
             expected_issue(:project_snapshot_tree_coverage_mismatch, :sheet, 12, "tree"),
             expected_issue(:project_snapshot_tree_coverage_mismatch, :sheet, 13, "tree")
           ]
  end

  test "locates every duplicate shortcut and every flow marked as main without retaining those values" do
    private_shortcut = "private-author-shortcut-do-not-store"

    snapshot =
      project_snapshot(
        sheets: [sheet_entry(11, private_shortcut), sheet_entry(12, private_shortcut)],
        flows: [flow_entry(21, "first-flow", true), flow_entry(22, "second-flow", true)],
        tree_sheets: [tree_entry(11), tree_entry(12)],
        tree_flows: [tree_entry(21), tree_entry(22)]
      )

    issues = SnapshotProjectContentHealth.issues(snapshot, @project_id)

    assert Enum.filter(issues, &(&1.code == :duplicate_project_snapshot_root_field)) == [
             expected_issue(:duplicate_project_snapshot_root_field, :sheet, 11, "shortcut"),
             expected_issue(:duplicate_project_snapshot_root_field, :sheet, 12, "shortcut")
           ]

    assert Enum.filter(issues, &(&1.code == :invalid_project_snapshot_main_flow_count)) == [
             expected_issue(:invalid_project_snapshot_main_flow_count, :flow, 21, "is_main"),
             expected_issue(:invalid_project_snapshot_main_flow_count, :flow, 22, "is_main")
           ]

    refute Jason.encode!(issues) =~ private_shortcut
  end

  test "finds dialogue localization identifiers duplicated across flows without retaining the identifier" do
    private_localization_id = "private-dialogue-localization-id-do-not-store"

    snapshot =
      project_snapshot(
        flows: [
          flow_entry(21, "first-flow", false, [dialogue_node(101, private_localization_id)]),
          flow_entry(22, "second-flow", false, [dialogue_node(102, private_localization_id)])
        ],
        tree_flows: [tree_entry(21), tree_entry(22)]
      )

    issues = SnapshotProjectContentHealth.issues(snapshot, @project_id)

    assert issues == [
             expected_issue(
               :duplicate_snapshot_dialogue_localization_id,
               :flow_node,
               101,
               "localization_id",
               :flow,
               21
             ),
             expected_issue(
               :duplicate_snapshot_dialogue_localization_id,
               :flow_node,
               102,
               "localization_id",
               :flow,
               22
             )
           ]

    refute Jason.encode!(issues) =~ private_localization_id
  end

  test "reports global and nested localization coverage and row drift without retaining editorial data" do
    private_locale = "private-locale-do-not-store"
    private_global_text = "private global text do not store"
    private_nested_text = "private nested text do not store"

    nested_only = localization_row("block", 111, "value.content", private_locale, private_nested_text)

    nested_mismatch =
      localization_row("sheet", 11, "name", private_locale, private_nested_text)

    global_only =
      "block"
      |> localization_row(112, "value.content", private_locale, private_global_text)
      |> Map.merge(%{"content_role" => "runtime_value", "vo_eligible" => false})

    global_mismatch =
      "sheet"
      |> localization_row(11, "name", private_locale, private_global_text)
      |> Map.merge(%{"content_role" => "speaker_name", "vo_eligible" => false})

    snapshot =
      project_snapshot(
        sheets: [
          sheet_entry(11, "localized-sheet", [block(111), block(112)], [nested_only, nested_mismatch])
        ],
        tree_sheets: [tree_entry(11)],
        localization: %{
          "languages" => [
            %{
              "locale_code" => private_locale,
              "is_source" => false,
              "archived_at" => nil
            }
          ],
          "texts" => [global_mismatch, global_only],
          "glossary" => []
        }
      )

    issues = SnapshotProjectContentHealth.issues(snapshot, @project_id)

    assert issues == [
             expected_issue(
               :project_snapshot_runtime_localization_coverage_mismatch,
               :block,
               111,
               "value.content",
               :sheet,
               11
             ),
             expected_issue(
               :project_snapshot_runtime_localization_coverage_mismatch,
               :block,
               112,
               "value.content",
               :sheet,
               11
             ),
             expected_issue(
               :project_snapshot_runtime_localization_row_mismatch,
               :sheet,
               11,
               "name",
               :sheet,
               11
             )
           ]

    encoded = Jason.encode!(issues)
    refute encoded =~ private_locale
    refute encoded =~ private_global_text
    refute encoded =~ private_nested_text

    reversed =
      snapshot
      |> update_in(["localization", "texts"], &Enum.reverse/1)
      |> update_in(["sheets", Access.at(0), "snapshot", "localization"], &Enum.reverse/1)

    assert SnapshotProjectContentHealth.issues(reversed, @project_id) == issues
  end

  test "reports active rows outside both the captured source and locale inventory" do
    row =
      "flow_node"
      |> localization_row(999, "text", "zz", "private raw row")
      |> Map.merge(%{"content_role" => "runtime_text", "vo_eligible" => true})

    snapshot =
      project_snapshot(
        localization: %{
          "languages" => [
            %{"locale_code" => "es", "is_source" => false, "archived_at" => nil}
          ],
          "texts" => [row],
          "glossary" => []
        }
      )

    issues = SnapshotProjectContentHealth.issues(snapshot, @project_id)

    assert MapSet.new(issues, & &1.code) ==
             MapSet.new([
               :localization_locale_outside_snapshot,
               :localization_source_outside_snapshot,
               :project_snapshot_runtime_localization_coverage_mismatch
             ])

    refute Jason.encode!(issues) =~ "private raw row"
  end

  test "accepts every active captured language including the source locale" do
    nested = localization_row("sheet", 11, "name", "en", "source-locale row")

    global =
      Map.merge(nested, %{"content_role" => "speaker_name", "vo_eligible" => false})

    snapshot =
      project_snapshot(
        sheets: [sheet_entry(11, "localized-sheet", [], [nested])],
        tree_sheets: [tree_entry(11)],
        localization: %{
          "languages" => [
            %{"locale_code" => "en", "is_source" => true, "archived_at" => nil}
          ],
          "texts" => [global],
          "glossary" => []
        }
      )

    assert SnapshotProjectContentHealth.issues(snapshot, @project_id) == []
  end

  test "reports a present source whose field is outside the localization contract" do
    private_field = "private-non-localizable-field"
    row = localization_row("sheet", 11, private_field, "es", "private raw row")

    snapshot =
      project_snapshot(
        sheets: [sheet_entry(11, "localized-sheet")],
        tree_sheets: [tree_entry(11)],
        localization: %{
          "languages" => [
            %{"locale_code" => "es", "is_source" => false, "archived_at" => nil}
          ],
          "texts" => [row],
          "glossary" => []
        }
      )

    issues = SnapshotProjectContentHealth.issues(snapshot, @project_id)

    assert Enum.filter(issues, &(&1.code == :localization_source_outside_snapshot)) == [
             expected_issue(
               :localization_source_outside_snapshot,
               :project,
               @project_id,
               "localization"
             )
           ]

    refute Jason.encode!(issues) =~ private_field
    refute Jason.encode!(issues) =~ "private raw row"
  end

  defp project_snapshot(opts) do
    sheets = Keyword.get(opts, :sheets, [])
    flows = Keyword.get(opts, :flows, [])
    scenes = Keyword.get(opts, :scenes, [])

    %{
      "format_version" => 2,
      "sheets" => sheets,
      "flows" => flows,
      "scenes" => scenes,
      "tree" => %{
        "sheets" => Keyword.get(opts, :tree_sheets, default_tree(sheets)),
        "flows" => Keyword.get(opts, :tree_flows, default_tree(flows)),
        "scenes" => Keyword.get(opts, :tree_scenes, default_tree(scenes))
      },
      "localization" => Keyword.get(opts, :localization, %{"languages" => [], "texts" => [], "glossary" => []})
    }
  end

  defp sheet_entry(id, shortcut, blocks \\ [], localization \\ []) do
    %{
      "id" => id,
      "snapshot" => %{
        "original_id" => id,
        "shortcut" => shortcut,
        "blocks" => blocks,
        "localization" => localization
      }
    }
  end

  defp flow_entry(id, shortcut, is_main, nodes \\ []) do
    %{
      "id" => id,
      "snapshot" => %{
        "original_id" => id,
        "shortcut" => shortcut,
        "is_main" => is_main,
        "nodes" => nodes,
        "localization" => []
      }
    }
  end

  defp dialogue_node(id, localization_id) do
    %{
      "original_id" => id,
      "type" => "dialogue",
      "data" => %{"localization_id" => localization_id}
    }
  end

  defp block(id), do: %{"original_id" => id}

  defp tree_entry(id, parent_id \\ nil) do
    %{"id" => id, "parent_id" => parent_id, "position" => 0}
  end

  defp default_tree(entries) do
    Enum.map(entries, &tree_entry(&1["id"]))
  end

  defp localization_row(source_type, source_id, source_field, locale, source_text) do
    %{
      "source_type" => source_type,
      "source_id" => source_id,
      "source_field" => source_field,
      "locale_code" => locale,
      "source_text" => source_text,
      "source_text_hash" => "hash",
      "archived_at" => nil
    }
  end

  defp expected_issue(code, entity_type, entity_id, source_field, container_type \\ :project, container_id \\ @project_id) do
    %{
      code: code,
      severity: :warning,
      entity_type: entity_type,
      entity_id: entity_id,
      source_field: source_field,
      impact: :restore_blocked,
      container_type: container_type,
      container_id: container_id
    }
  end
end
