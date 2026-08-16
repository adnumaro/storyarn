defmodule Storyarn.Versioning.SnapshotContentHealthTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotContentHealth

  test "unassessed content blocks exact restore without invalidating the report" do
    report = SnapshotContentHealth.unknown()

    assert :ok = SnapshotContentHealth.validate(report)
    assert SnapshotContentHealth.restore_blocked?(report)
  end

  test "builds a deterministic sanitized report from capture and canonical findings" do
    canonical =
      SnapshotContentHealth.canonical_issues(:flow, [
        %{
          code: :missing_entry,
          severity: :error,
          flow_id: 42,
          entity_type: :flow,
          entity_id: 42,
          details: %{flow_name: "secret author title"}
        }
      ])

    report =
      SnapshotContentHealth.build([
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
        | canonical
      ])

    assert report["state"] == "warnings"
    assert report["issue_count"] == 2
    assert report["impact_counts"] == %{"restore_blocked" => 1, "runtime_degraded" => 1}
    assert report["issue_counts_by_code"]["capture.localization_speaker_mismatch"] == 1
    assert report["issue_counts_by_code"]["flow.missing_entry"] == 1
    assert SnapshotContentHealth.restore_blocked?(report)
    refute inspect(report) =~ "secret author title"
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

  test "replaces a truncated issue family with the exact authoritative inventory" do
    prior_issues =
      for entity_id <- 1..55 do
        %{
          code: :avatar_project_mismatch,
          severity: :warning,
          entity_type: :flow_node,
          entity_id: entity_id,
          source_field: :avatar_id,
          impact: :restore_blocked,
          container_type: :flow,
          container_id: 42
        }
      end

    partial_asset_issue = asset_issue(901)
    report = SnapshotContentHealth.build([partial_asset_issue | prior_issues])
    assert report["issues_truncated"]
    refute partial_asset_issue in report["issues"]

    replaced =
      SnapshotContentHealth.replace_issue_family(
        report,
        :capture,
        :invalid_asset_snapshot_content,
        [asset_issue(902), asset_issue(903)]
      )

    assert :ok = SnapshotContentHealth.validate(replaced)
    assert replaced["issue_count"] == 57
    assert replaced["issue_counts_by_code"]["capture.invalid_asset_snapshot_content"] == 2
    assert replaced["issues_truncated"]
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

  defp asset_issue(asset_id) do
    %{
      code: :invalid_asset_snapshot_content,
      severity: :warning,
      entity_type: :asset,
      entity_id: asset_id,
      source_field: :metadata,
      impact: :restore_blocked,
      container_type: :project,
      container_id: 7
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
