defmodule Storyarn.ProjectTemplates.LegacySnapshotRepairTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.LegacySnapshotRepair
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    _hub = node_fixture(flow, %{type: "hub", data: %{}, position_x: 400.0, position_y: 100.0})
    {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Legacy sequence"})

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    %{
      user: user,
      project: project,
      flow: flow,
      sequence: sequence,
      snapshot: snapshot,
      legacy_snapshot: make_legacy_snapshot(snapshot)
    }
  end

  test "repairs a homogeneous unconnected legacy sequence and materializes it", %{
    user: user,
    project: project,
    flow: flow,
    sequence: sequence,
    legacy_snapshot: legacy_snapshot
  } do
    assert {:error, _errors} = Audit.validate_snapshot_integrity(legacy_snapshot)

    {legacy_node, legacy_index} = snapshot_node(legacy_snapshot, flow.id, sequence.id)

    assert {:ok, repaired_snapshot, report} = LegacySnapshotRepair.repair(legacy_snapshot)

    assert report["status"] == "repaired_with_warnings"
    assert report["repaired_sequence_count"] == 1

    assert [
             %{
               "flow_id" => flow.id,
               "node_id" => sequence.id,
               "node_index" => legacy_index
             }
           ] == report["repaired_sequences"]

    {repaired_node, repaired_index} = snapshot_node(repaired_snapshot, flow.id, sequence.id)

    assert repaired_index == legacy_index
    assert repaired_node["type"] == "annotation"

    assert Map.take(repaired_node, [
             "original_id",
             "position_x",
             "position_y",
             "source",
             "word_count"
           ]) ==
             Map.take(legacy_node, [
               "original_id",
               "position_x",
               "position_y",
               "source",
               "word_count"
             ])

    assert get_in(repaired_node, ["data", "legacy_recovery"]) == %{
             "original_id" => sequence.id,
             "original_type" => "sequence"
           }

    refute Map.has_key?(repaired_node, "sequence_config")
    refute Map.has_key?(repaired_node, "sequence_tracks")
    refute Map.has_key?(repaired_node, "sequence_visual_layers")

    assert {:ok, materialization_report} =
             Audit.verify_snapshot_materialization(
               repaired_snapshot,
               project.workspace_id,
               user.id
             )

    assert materialization_report["status"] == "passed"
    assert materialization_report["errors"] == []
    assert materialization_report["snapshot_counts"] == materialization_report["recovered_counts"]
    assert materialization_report["recovered_counts"]["sequence_configs"] == 0
  end

  test "rejects a connected legacy sequence", %{
    flow: flow,
    sequence: sequence,
    legacy_snapshot: legacy_snapshot
  } do
    {sequence_node, sequence_index} = snapshot_node(legacy_snapshot, flow.id, sequence.id)
    {other_node, other_index} = non_sequence_snapshot_node(legacy_snapshot, flow.id)

    connection = %{
      "original_id" => System.unique_integer([:positive]),
      "source_node_index" => other_index,
      "source_pin" => "output",
      "target_node_index" => sequence_index,
      "target_pin" => "input",
      "label" => nil
    }

    connected_snapshot =
      update_flow_snapshot(legacy_snapshot, flow.id, fn flow_snapshot ->
        Map.put(flow_snapshot, "connections", [connection])
      end)

    assert sequence_node["type"] == "sequence"
    refute other_node["type"] == "sequence"

    assert {:error, {:connected_legacy_sequence, flow_id}} =
             LegacySnapshotRepair.repair(connected_snapshot)

    assert flow_id == flow.id
  end

  test "rejects non-list localization texts without raising", %{
    legacy_snapshot: legacy_snapshot
  } do
    malformed = put_localization_value(legacy_snapshot, "texts", "not-a-list")

    assert {:error, _reason} = LegacySnapshotRepair.repair(malformed)
  end

  test "rejects malformed localization language entries without raising", %{
    legacy_snapshot: legacy_snapshot
  } do
    malformed = put_localization_value(legacy_snapshot, "languages", [42])

    assert {:error, _reason} = LegacySnapshotRepair.repair(malformed)
  end

  test "rejects non-list localization glossary without raising", %{
    legacy_snapshot: legacy_snapshot
  } do
    malformed = put_localization_value(legacy_snapshot, "glossary", "not-a-list")

    assert {:error, _reason} = LegacySnapshotRepair.repair(malformed)
  end

  test "removes known legacy block metadata shapes and preserves runtime rows", %{
    legacy_snapshot: legacy_snapshot
  } do
    sheet_id = System.unique_integer([:positive])
    select_id = System.unique_integer([:positive])
    table_id = System.unique_integer([:positive])
    gallery_id = System.unique_integer([:positive])

    sheet_entry = %{
      "id" => sheet_id,
      "snapshot" => %{
        "original_id" => sheet_id,
        "name" => "Speaker",
        "blocks" => [
          %{
            "original_id" => select_id,
            "type" => "select",
            "config" => %{
              "options" => [%{"key" => "hero.path", "value" => "Hero"}]
            }
          },
          %{
            "original_id" => table_id,
            "type" => "table",
            "table_data" => %{
              "columns" => [%{"name" => "Rank"}],
              "rows" => [%{"name" => "Vanguard"}]
            }
          },
          %{
            "original_id" => gallery_id,
            "type" => "gallery",
            "gallery_images" => [
              %{"original_id" => 91, "label" => "Portrait", "description" => nil}
            ]
          }
        ]
      }
    }

    runtime_row = localization_row("sheet", sheet_id, "name", "Speaker")

    legacy_rows = [
      localization_row("block", select_id, "config.options.hero.path", "Hero"),
      localization_row("block", table_id, "table_column.123.name", "Rank"),
      localization_row("block", table_id, "table_row.456.name", "Vanguard"),
      localization_row("block", gallery_id, "gallery_image.91.label", "Portrait")
    ]

    snapshot =
      legacy_snapshot
      |> Map.put("sheets", [sheet_entry])
      |> Map.put("scenes", [])
      |> Map.put("localization", %{
        "languages" => [
          %{"locale_code" => "es", "name" => "Spanish", "is_source" => false, "position" => 0}
        ],
        "texts" => [runtime_row | legacy_rows],
        "glossary" => []
      })

    assert {:ok, repaired, report} = LegacySnapshotRepair.repair(snapshot)
    assert get_in(repaired, ["localization", "texts"]) == [runtime_row]
    assert report["localization"]["kept_count"] == 1
    assert report["localization"]["removed_count"] == 4
  end

  test "rejects duplicate flow and node ids across the snapshot", %{
    legacy_snapshot: legacy_snapshot
  } do
    [flow_entry] = legacy_snapshot["flows"]
    duplicated = Map.put(legacy_snapshot, "flows", [flow_entry, flow_entry])

    assert {:error, _reason} = LegacySnapshotRepair.repair(duplicated)
  end

  test "rejects malformed connection indexes before materialization", %{
    flow: flow,
    sequence: sequence,
    legacy_snapshot: legacy_snapshot
  } do
    {_sequence_node, sequence_index} = snapshot_node(legacy_snapshot, flow.id, sequence.id)
    {_other_node, other_index} = non_sequence_snapshot_node(legacy_snapshot, flow.id)

    connection = %{
      "original_id" => System.unique_integer([:positive]),
      "source_node_index" => Integer.to_string(sequence_index),
      "source_pin" => "output",
      "target_node_index" => other_index,
      "target_pin" => "input",
      "label" => nil
    }

    malformed =
      update_flow_snapshot(legacy_snapshot, flow.id, fn flow_snapshot ->
        Map.put(flow_snapshot, "connections", [connection])
      end)

    assert {:error, _reason} = LegacySnapshotRepair.repair(malformed)
  end

  test "rejects a snapshot that mixes legacy and current sequence shapes", %{
    project: project,
    flow: flow,
    sequence: legacy_sequence
  } do
    {:ok, current_sequence} = Flows.create_sequence(flow.id, %{"name" => "Current sequence"})

    mixed_snapshot =
      project.id
      |> ProjectSnapshotBuilder.build_snapshot()
      |> make_legacy_snapshot(MapSet.new([legacy_sequence.id]))

    {legacy_node, _legacy_index} = snapshot_node(mixed_snapshot, flow.id, legacy_sequence.id)
    {current_node, _current_index} = snapshot_node(mixed_snapshot, flow.id, current_sequence.id)

    refute Map.has_key?(legacy_node, "sequence_config")
    assert is_map(current_node["sequence_config"])
    assert is_list(current_node["sequence_tracks"])
    assert is_list(current_node["sequence_visual_layers"])

    assert {:error, _reason} = LegacySnapshotRepair.repair(mixed_snapshot)
  end

  test "rejects an unsupported project snapshot format", %{
    legacy_snapshot: legacy_snapshot
  } do
    future_snapshot = Map.put(legacy_snapshot, "format_version", 999)

    assert {:error, _reason} = LegacySnapshotRepair.repair(future_snapshot)
  end

  defp make_legacy_snapshot(snapshot, target_ids \\ :all) do
    update_in(snapshot, ["flows", Access.all(), "snapshot", "nodes", Access.all()], fn node ->
      node = Map.delete(node, "parent_id")

      if legacy_target?(node, target_ids) do
        node
        |> Map.delete("sequence_config")
        |> Map.delete("sequence_tracks")
        |> Map.delete("sequence_visual_layers")
      else
        node
      end
    end)
  end

  defp legacy_target?(%{"type" => "sequence"}, :all), do: true

  defp legacy_target?(%{"type" => "sequence", "original_id" => original_id}, %MapSet{} = target_ids) do
    MapSet.member?(target_ids, original_id)
  end

  defp legacy_target?(_node, _target_ids), do: false

  defp snapshot_node(snapshot, flow_id, node_id) do
    nodes = flow_snapshot(snapshot, flow_id)["nodes"]

    nodes
    |> Enum.with_index()
    |> Enum.find(fn {node, _index} -> node["original_id"] == node_id end)
  end

  defp non_sequence_snapshot_node(snapshot, flow_id) do
    nodes = flow_snapshot(snapshot, flow_id)["nodes"]

    nodes
    |> Enum.with_index()
    |> Enum.find(fn {node, _index} -> node["type"] != "sequence" end)
  end

  defp update_flow_snapshot(snapshot, flow_id, update_fun) do
    update_in(snapshot, ["flows"], fn flows ->
      Enum.map(flows, fn
        %{"id" => ^flow_id, "snapshot" => flow_snapshot} = flow_entry ->
          Map.put(flow_entry, "snapshot", update_fun.(flow_snapshot))

        flow_entry ->
          flow_entry
      end)
    end)
  end

  defp flow_snapshot(snapshot, flow_id) do
    snapshot["flows"]
    |> Enum.find(&(&1["id"] == flow_id))
    |> Map.fetch!("snapshot")
  end

  defp put_localization_value(snapshot, key, value) do
    localization = Map.get(snapshot, "localization") || %{}
    Map.put(snapshot, "localization", Map.put(localization, key, value))
  end

  defp localization_row(source_type, source_id, source_field, source_text) do
    %{
      "source_type" => source_type,
      "source_id" => source_id,
      "source_field" => source_field,
      "source_text" => source_text,
      "source_text_hash" => sha256(source_text),
      "locale_code" => "es"
    }
  end

  defp sha256(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
