defmodule Storyarn.Versioning.SnapshotContentHealthTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotContentHealth

  test "unassessed content blocks exact restore without invalidating the report" do
    report = SnapshotContentHealth.unknown()

    assert :ok = SnapshotContentHealth.validate(report)
    assert SnapshotContentHealth.restore_blocked?(report)
  end

  test "strict legacy captures are assessed and remain restorable without findings" do
    report = SnapshotContentHealth.legacy_strict()

    assert :ok = SnapshotContentHealth.validate(report)
    assert report["state"] == "legacy_strict"
    assert report["issue_count"] == 0
    refute SnapshotContentHealth.restore_blocked?(report)
  end

  test "builds a deterministic sanitized report from capture findings" do
    report =
      SnapshotContentHealth.build([
        %{
          code: :invalid_project_snapshot_content,
          severity: :warning,
          entity_type: :project,
          entity_id: 7,
          impact: :runtime_degraded,
          container_type: :project,
          container_id: 7,
          details: %{flow_name: "secret author title"}
        },
        %{
          code: :localization_speaker_mismatch,
          severity: :warning,
          entity_type: :flow_node,
          entity_id: 101,
          source_field: "speaker_sheet_id",
          impact: :restore_blocked,
          container_type: :flow,
          container_id: 42
        }
      ])

    assert report["state"] == "warnings"
    assert report["issue_count"] == 2
    assert report["impact_counts"] == %{"restore_blocked" => 1, "runtime_degraded" => 1}
    assert report["issue_counts_by_code"]["capture.localization_speaker_mismatch"] == 1
    assert report["issue_counts_by_code"]["capture.invalid_project_snapshot_content"] == 1
    assert SnapshotContentHealth.restore_blocked?(report)
    refute inspect(report) =~ "secret author title"
    assert :ok = SnapshotContentHealth.validate(report)
  end

  test "a dashboard namespace cannot enter the durable report" do
    report =
      SnapshotContentHealth.build([
        %{
          domain: :flow,
          code: :missing_entry,
          severity: :error,
          entity_type: :flow,
          entity_id: 42,
          impact: :runtime_degraded,
          container_type: :flow,
          container_id: 42
        }
      ])

    assert report["issue_counts_by_code"] == %{"capture.unclassified_content_issue" => 1}
    assert report["issues"] |> hd() |> Map.fetch!("domain") == "capture"
    assert SnapshotContentHealth.restore_blocked?(report)
    assert :ok = SnapshotContentHealth.validate(report)
  end

  test "an unknown producer code becomes a generic restore blocker instead of false green" do
    report =
      SnapshotContentHealth.build([
        %{
          code: :future_unreviewed_reason,
          severity: :warning,
          entity_type: :flow,
          entity_id: 42,
          impact: :runtime_degraded,
          container_type: :flow,
          container_id: 42
        }
      ])

    assert report["state"] == "warnings"
    assert report["issue_count"] == 1
    assert report["issue_counts_by_code"] == %{"capture.unclassified_content_issue" => 1}
    assert report["impact_counts"]["restore_blocked"] == 1
    assert SnapshotContentHealth.restore_blocked?(report)
  end

  test "rebuilds from the full inventory without losing issues hidden by an earlier bound" do
    catalog_issues = Enum.map(1..55, &asset_catalog_issue/1)
    other_issues = Enum.map(101..110, &missing_asset_issue/1)
    initial = SnapshotContentHealth.build(catalog_issues ++ other_issues)

    assert initial["issue_count"] == 65
    assert initial["issues_truncated"]
    assert initial["issue_counts_by_code"]["capture.invalid_asset_catalog_content"] == 55
    assert initial["issue_counts_by_code"]["capture.missing_asset_reference"] == 10

    for {authoritative_catalog, expected_count} <- [
          {[asset_catalog_issue(201), asset_catalog_issue(202)], 12},
          {[], 10}
        ] do
      rebuilt = SnapshotContentHealth.build(other_issues ++ authoritative_catalog)

      assert :ok = SnapshotContentHealth.validate(rebuilt)
      assert rebuilt["issue_count"] == expected_count
      assert rebuilt["issue_counts_by_code"]["capture.missing_asset_reference"] == 10

      assert Map.get(rebuilt["issue_counts_by_code"], "capture.invalid_asset_catalog_content", 0) ==
               length(authoritative_catalog)

      refute rebuilt["issues_truncated"]
      refute Map.has_key?(rebuilt["issue_counts_by_code"], "capture.unclassified_content_issue")
      assert length(rebuilt["issues"]) == expected_count
    end
  end

  test "retains every current scene capture code instead of genericizing it" do
    codes = ~w(
      scene_snapshot_requires_at_least_one_layer
      invalid_scene_default_layer_count
      invalid_scene_snapshot_field
      missing_scene_snapshot_field
      invalid_scene_child_snapshot
      invalid_scene_zone_target_contract
      invalid_scene_zone_collection
      invalid_scene_zone_collection_item
      invalid_scene_connection_snapshot
      invalid_scene_connection_waypoints
      invalid_scene_connection_endpoint
      invalid_scene_ambient_flow_trigger_config
    )a

    issues =
      Enum.map(codes, fn code ->
        %{
          code: code,
          severity: :warning,
          entity_type: :scene,
          entity_id: 42,
          source_field: nil,
          impact: :restore_blocked,
          container_type: :scene,
          container_id: 42
        }
      end)

    report = SnapshotContentHealth.build(issues)

    assert report["issue_count"] == length(codes)
    refute Map.has_key?(report["issue_counts_by_code"], "capture.unclassified_content_issue")

    assert report["issue_counts_by_code"] |> Map.keys() |> Enum.sort() ==
             codes |> Enum.map(&"capture.#{&1}") |> Enum.sort()
  end

  defp asset_catalog_issue(asset_id) do
    %{
      code: :invalid_asset_catalog_content,
      severity: :warning,
      entity_type: :asset,
      entity_id: asset_id,
      source_field: :metadata,
      impact: :restore_blocked,
      container_type: :project,
      container_id: 7
    }
  end

  defp missing_asset_issue(entity_id) do
    %{
      code: :missing_asset_reference,
      severity: :warning,
      entity_type: :flow_node,
      entity_id: entity_id,
      source_field: :avatar_id,
      impact: :restore_blocked,
      container_type: :flow,
      container_id: 42
    }
  end

  test "retains only the bounded deterministic detail inventory while preserving totals" do
    issues =
      Enum.map(1..(SnapshotContentHealth.max_issues() + 7), fn id ->
        %{
          code: :missing_asset_reference,
          severity: :warning,
          entity_type: :flow_node,
          entity_id: id,
          source_field: "avatar_id",
          impact: :restore_blocked,
          container_type: :flow,
          container_id: 42
        }
      end)

    report = SnapshotContentHealth.build(Enum.reverse(issues))

    assert report["issue_count"] == 57
    assert report["issues_truncated"]
    assert length(report["issues"]) == SnapshotContentHealth.max_issues()
    assert report["issues"] == Enum.sort_by(report["issues"], &{&1["entity_id"]})
    assert :ok = SnapshotContentHealth.validate(report)
  end

  test "invalid persisted shapes are conservative for UI and fail closed for restore" do
    invalid = Map.put(SnapshotContentHealth.healthy(), "raw_reason", "private")

    assert {:error, :invalid_snapshot_content_health} = SnapshotContentHealth.validate(invalid)
    assert SnapshotContentHealth.safe(invalid) == SnapshotContentHealth.unknown()
    assert SnapshotContentHealth.restore_blocked?(invalid)
  end

  test "does not double-count an issue that may already be hidden by the detail bound" do
    issues =
      Enum.map(1..(SnapshotContentHealth.max_issues() + 1), fn id ->
        %{
          code: :invalid_project_snapshot_content,
          severity: :warning,
          entity_type: :project,
          entity_id: id,
          source_field: nil,
          impact: :restore_blocked,
          container_type: :project,
          container_id: id
        }
      end)

    report = SnapshotContentHealth.build(issues)
    hidden_issue = List.last(issues)

    assert SnapshotContentHealth.add_issue(report, hidden_issue) == report
    assert report["issue_count"] == SnapshotContentHealth.max_issues() + 1
    assert :ok = SnapshotContentHealth.validate(report)
  end
end
