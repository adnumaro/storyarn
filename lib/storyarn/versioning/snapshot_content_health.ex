defmodule Storyarn.Versioning.SnapshotContentHealth do
  @moduledoc """
  Bounded, portable content-health metadata captured with a project snapshot.

  Findings contain only catalog identifiers and database-local locations. Raw
  reasons, user-authored labels, referenced values, and exception details never
  enter the report. The report is deterministic so its JSON bytes remain bound
  to the canonical snapshot digest.
  """

  @version 1
  @max_issues 50
  @max_encoded_bytes 64 * 1024
  @max_pg_bigint 9_223_372_036_854_775_807
  @domains ~w(capture)
  @severities ~w(error warning info)
  @impacts ~w(restore_blocked runtime_degraded)
  @states ~w(unknown legacy_strict healthy warnings)
  @safe_identifier ~r/\A[a-z][a-z0-9_.-]{0,127}\z/
  @safe_location_id ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,99}\z/

  @capture_codes MapSet.new(~w(
    avatar_project_mismatch
    avatar_speaker_mismatch
    circular_flow_reference
    cross_project_asset_reference
    dynamic_exit_pin_not_materializable
    flow_external_reference_not_materializable
    inactive_asset_reference
    incomplete_flow_localization_snapshot
    incomplete_localization
    inheritance_cycle
    invalid_active_localization_archive_state
    invalid_asset_catalog_content
    invalid_asset_reference
    invalid_asset_snapshot_content
    invalid_avatar_reference
    invalid_block_reference
    invalid_localization_placeholders
    invalid_localization_translation_state
    invalid_localization_voiceover_state
    invalid_project_snapshot_content
    invalid_project_snapshot_main_flow_count
    invalid_project_snapshot_tree_parent
    invalid_flow_connection
    invalid_flow_external_reference
    invalid_flow_exit_target
    invalid_flow_graph
    invalid_flow_localization
    invalid_flow_localization_snapshot
    invalid_flow_localization_source_node
    invalid_flow_localization_source_nodes
    invalid_flow_node
    invalid_flow_snapshot
    invalid_localization_target_locales
    invalid_scene_asset_content_type
    invalid_scene_connection_route
    invalid_scene_external_reference
    invalid_scene_ambient_flow_trigger_config
    invalid_scene_child_snapshot
    invalid_scene_connection_endpoint
    invalid_scene_connection_snapshot
    invalid_scene_connection_waypoints
    invalid_scene_default_layer_count
    invalid_scene_snapshot_field
    invalid_scene_snapshot_content
    invalid_scene_variable_reference
    invalid_scene_zone_collection
    invalid_scene_zone_collection_item
    invalid_scene_zone_target_contract
    invalid_sequence_config_snapshot
    invalid_sequence_snapshot_collection
    invalid_sequence_track_snapshot
    invalid_sequence_visual_layer_snapshot
    invalid_sheet_snapshot_content
    invalid_snapshot_connection
    invalid_snapshot_connection_endpoint
    invalid_snapshot_connection_label
    invalid_snapshot_connection_pin
    invalid_snapshot_dialogue_localization_id
    invalid_snapshot_dialogue_response_id
    invalid_snapshot_dialogue_responses
    invalid_snapshot_entry_count
    invalid_snapshot_exit_count
    invalid_snapshot_field
    invalid_snapshot_fields
    invalid_snapshot_node
    invalid_snapshot_node_parent
    invalid_snapshot_node_parent_id
    invalid_snapshot_node_type
    invalid_snapshot_original_id
    invalid_snapshot_self_connection
    invalid_snapshot_sequence_connection
    localization_locale_outside_snapshot
    localization_source_outside_snapshot
    localization_source_text_hash_mismatch
    localization_source_text_mismatch
    localization_speaker_mismatch
    localization_word_count_mismatch
    missing_sequence_config_snapshot
    missing_sequence_snapshot_collection
    missing_asset_reference
    missing_scene_snapshot_field
    missing_snapshot_fields
    scene_child_layer_not_in_scene
    scene_connection_pin_not_in_snapshot
    scene_snapshot_requires_at_least_one_layer
    scene_reference_not_found
    scene_reference_project_mismatch
    snapshot_node_parent_cycle
    duplicate_project_snapshot_root_field
    duplicate_flow_localization_snapshot
    duplicate_sequence_track_kind
    duplicate_snapshot_connection
    duplicate_snapshot_dialogue_localization_id
    duplicate_snapshot_dialogue_response_id
    duplicate_snapshot_original_id
    project_snapshot_runtime_localization_coverage_mismatch
    project_snapshot_runtime_localization_row_mismatch
    project_snapshot_tree_coverage_mismatch
    project_snapshot_tree_cycle
    unclassified_content_issue
  ))

  @report_keys ~w(
    impact_counts
    issue_count
    issue_counts_by_code
    issues
    issues_truncated
    severity_counts
    state
    version
  )
  @issue_keys ~w(
    code
    container_id
    container_type
    domain
    entity_id
    entity_type
    impact
    severity
    source_field
  )

  @type report :: map()

  @doc "The conservative value assigned before a capture has been assessed."
  @spec unknown() :: report()
  def unknown do
    empty_report("unknown")
  end

  @doc "An assessed legacy report produced by the strict pre-health snapshot pipeline."
  @spec legacy_strict() :: report()
  def legacy_strict do
    empty_report("legacy_strict")
  end

  @doc "An assessed report with no content findings."
  @spec healthy() :: report()
  def healthy do
    empty_report("healthy")
  end

  @doc "Maximum number of located findings retained in the portable report."
  @spec max_issues() :: pos_integer()
  def max_issues, do: @max_issues

  @doc "Builds a deterministic report or returns `unknown/0` for an invalid producer shape."
  @spec build([map()]) :: report()
  def build(issues) when is_list(issues) do
    issues
    |> Enum.map(&normalize_issue_or_fallback/1)
    |> Enum.uniq()
    |> Enum.sort_by(&issue_sort_key/1)
    |> build_report()
    |> safe()
  end

  def build(_issues), do: build([%{}])

  @doc false
  @spec add_issue(report(), map()) :: report()
  def add_issue(report, issue) do
    normalized = normalize_issue_or_fallback(issue)

    case validate(report) do
      :ok -> add_normalized_issue(report, normalized)
      {:error, :invalid_snapshot_content_health} -> build([normalized])
    end
  end

  @doc "Returns the report only when it satisfies the complete portable contract."
  @spec validate(term()) :: :ok | {:error, :invalid_snapshot_content_health}
  def validate(report) do
    if valid_report?(report), do: :ok, else: {:error, :invalid_snapshot_content_health}
  end

  @doc "Sanitizes untrusted or legacy values to the conservative unknown state."
  @spec safe(term()) :: report()
  def safe(report) do
    if valid_report?(report), do: report, else: unknown()
  end

  @doc "Whether exact restore is blocked by unassessed or unrestorable captured content."
  @spec restore_blocked?(term()) :: boolean()
  def restore_blocked?(report) do
    case validate(report) do
      :ok -> report["state"] == "unknown" or get_in(report, ["impact_counts", "restore_blocked"]) > 0
      {:error, :invalid_snapshot_content_health} -> true
    end
  end

  defp empty_report(state) do
    %{
      "impact_counts" => %{"restore_blocked" => 0, "runtime_degraded" => 0},
      "issue_count" => 0,
      "issue_counts_by_code" => %{},
      "issues" => [],
      "issues_truncated" => false,
      "severity_counts" => %{"error" => 0, "warning" => 0, "info" => 0},
      "state" => state,
      "version" => @version
    }
  end

  defp normalize_issue_or_fallback(issue) do
    case normalize_issue(issue) do
      {:ok, normalized} -> normalized
      :error -> unclassified_issue()
    end
  end

  defp normalize_issue(issue) when is_map(issue) do
    normalized = %{
      "code" => issue |> field(:code) |> normalize_string(),
      "container_id" => issue |> field(:container_id) |> normalize_location_id(),
      "container_type" => issue |> field(:container_type) |> normalize_optional_identifier(),
      "domain" => issue |> field(:domain) |> Kernel.||(:capture) |> normalize_string(),
      "entity_id" => issue |> field(:entity_id) |> normalize_location_id(),
      "entity_type" => issue |> field(:entity_type) |> normalize_string(),
      "impact" => issue |> field(:impact) |> normalize_string(),
      "severity" => issue |> field(:severity) |> normalize_string(),
      "source_field" => issue |> field(:source_field) |> normalize_optional_identifier()
    }

    if valid_normalized_issue?(normalized), do: {:ok, normalized}, else: :error
  end

  defp normalize_issue(_issue), do: :error

  defp unclassified_issue do
    %{
      "code" => "unclassified_content_issue",
      "container_id" => "current",
      "container_type" => "snapshot",
      "domain" => "capture",
      "entity_id" => nil,
      "entity_type" => "content",
      "impact" => "restore_blocked",
      "severity" => "error",
      "source_field" => nil
    }
  end

  defp build_report([]), do: healthy()

  defp build_report(issues) do
    issue_count = length(issues)

    %{
      "impact_counts" => counts(issues, "impact", @impacts),
      "issue_count" => issue_count,
      "issue_counts_by_code" => Enum.frequencies_by(issues, &qualified_code/1),
      "issues" => Enum.take(issues, @max_issues),
      "issues_truncated" => issue_count > @max_issues,
      "severity_counts" => counts(issues, "severity", @severities),
      "state" => "warnings",
      "version" => @version
    }
  end

  defp add_normalized_issue(%{"issues" => issues} = report, normalized) do
    if normalized in issues or hidden_summary_may_contain?(report, normalized) do
      report
    else
      issue_count = report["issue_count"] + 1

      report
      |> Map.put("issue_count", issue_count)
      |> Map.put(
        "issue_counts_by_code",
        Map.update(report["issue_counts_by_code"], qualified_code(normalized), 1, &(&1 + 1))
      )
      |> Map.put(
        "impact_counts",
        Map.update!(report["impact_counts"], normalized["impact"], &(&1 + 1))
      )
      |> Map.put(
        "severity_counts",
        Map.update!(report["severity_counts"], normalized["severity"], &(&1 + 1))
      )
      |> Map.put("issues", issues |> Kernel.++([normalized]) |> Enum.sort_by(&issue_sort_key/1) |> Enum.take(@max_issues))
      |> Map.put("issues_truncated", issue_count > @max_issues)
      |> Map.put("state", "warnings")
      |> safe()
    end
  end

  defp hidden_summary_may_contain?(%{"issues_truncated" => true} = report, normalized) do
    qualified = qualified_code(normalized)
    retained_count = Enum.count(report["issues"], &(qualified_code(&1) == qualified))
    Map.get(report["issue_counts_by_code"], qualified, 0) > retained_count
  end

  defp hidden_summary_may_contain?(_report, _normalized), do: false

  defp counts(issues, field_name, values) do
    frequencies = Enum.frequencies_by(issues, & &1[field_name])
    Map.new(values, &{&1, Map.get(frequencies, &1, 0)})
  end

  defp qualified_code(issue), do: issue["domain"] <> "." <> issue["code"]

  defp valid_report?(report) when is_map(report) do
    with true <- Enum.sort(Map.keys(report)) == @report_keys,
         @version <- report["version"],
         state when state in @states <- report["state"],
         count when is_integer(count) and count >= 0 and count <= @max_pg_bigint <- report["issue_count"],
         truncated when is_boolean(truncated) <- report["issues_truncated"],
         issues when is_list(issues) and length(issues) <= @max_issues <- report["issues"],
         code_counts when is_map(code_counts) <- report["issue_counts_by_code"],
         impact_counts when is_map(impact_counts) <- report["impact_counts"],
         severity_counts when is_map(severity_counts) <- report["severity_counts"],
         true <- valid_count_map?(code_counts, count, :codes),
         true <- valid_fixed_counts?(impact_counts, @impacts, count),
         true <- valid_fixed_counts?(severity_counts, @severities, count),
         true <-
           valid_report_issues?(
             issues,
             count,
             truncated,
             code_counts,
             impact_counts,
             severity_counts
           ),
         true <- valid_state?(state, count),
         {:ok, encoded} <- Jason.encode(report),
         true <- byte_size(encoded) <= @max_encoded_bytes do
      true
    else
      _invalid -> false
    end
  end

  defp valid_report?(_report), do: false

  defp valid_count_map?(counts, expected, :codes) do
    Enum.all?(counts, fn {qualified, count} ->
      case String.split(qualified, ".", parts: 2) do
        [domain, code] -> valid_code?(domain, code) and is_integer(count) and count > 0
        _invalid -> false
      end
    end) and Enum.sum(Map.values(counts)) == expected
  end

  defp valid_fixed_counts?(counts, keys, expected) do
    counts |> Map.keys() |> Enum.sort() == Enum.sort(keys) and
      Enum.all?(counts, fn {_key, count} -> is_integer(count) and count >= 0 end) and
      Enum.sum(Map.values(counts)) == expected
  end

  defp valid_report_issues?(issues, count, truncated, code_counts, impact_counts, severity_counts) do
    Enum.all?(issues, &valid_normalized_issue?/1) and
      issues == Enum.sort_by(Enum.uniq(issues), &issue_sort_key/1) and
      valid_detail_count?(length(issues), count, truncated) and
      detail_counts_within_summary?(issues, code_counts, impact_counts, severity_counts)
  end

  defp valid_detail_count?(count, count, false), do: count <= @max_issues

  defp valid_detail_count?(@max_issues, count, true), do: count > @max_issues

  defp valid_detail_count?(_detail_count, _count, _truncated), do: false

  defp detail_counts_within_summary?(issues, code_counts, impact_counts, severity_counts) do
    detail_count_maps = [
      Enum.frequencies_by(issues, &qualified_code/1),
      Enum.frequencies_by(issues, & &1["impact"]),
      Enum.frequencies_by(issues, & &1["severity"])
    ]

    summary_count_maps = [code_counts, impact_counts, severity_counts]

    detail_count_maps
    |> Enum.zip_with(summary_count_maps, fn details, summary ->
      Enum.all?(details, fn {key, count} -> count <= Map.get(summary, key, 0) end)
    end)
    |> Enum.all?()
  end

  defp valid_normalized_issue?(issue) when is_map(issue) do
    exact_issue_shape?(issue) and valid_issue_classification?(issue) and valid_issue_location?(issue)
  end

  defp valid_normalized_issue?(_issue), do: false

  defp exact_issue_shape?(issue), do: Enum.sort(Map.keys(issue)) == @issue_keys

  defp valid_issue_classification?(issue) do
    issue["domain"] in @domains and valid_code?(issue["domain"], issue["code"]) and
      issue["severity"] in @severities and issue["impact"] in @impacts
  end

  defp valid_issue_location?(issue) do
    valid_identifier?(issue["entity_type"]) and
      valid_optional_identifier?(issue["source_field"]) and
      valid_optional_identifier?(issue["container_type"]) and
      valid_location_id?(issue["entity_id"]) and
      valid_location_id?(issue["container_id"]) and
      not (is_nil(issue["entity_id"]) and is_nil(issue["container_id"]))
  end

  defp valid_state?("unknown", 0), do: true
  defp valid_state?("legacy_strict", 0), do: true
  defp valid_state?("healthy", 0), do: true
  defp valid_state?("warnings", count), do: count > 0
  defp valid_state?(_state, _count), do: false

  defp valid_code?("capture", code), do: MapSet.member?(@capture_codes, code)
  defp valid_code?(_domain, _code), do: false

  defp valid_identifier?(value), do: is_binary(value) and Regex.match?(@safe_identifier, value)

  defp normalize_optional_identifier(nil), do: nil

  defp normalize_optional_identifier(value) do
    value = normalize_string(value)
    if valid_identifier?(value), do: value, else: :error
  end

  defp valid_optional_identifier?(nil), do: true
  defp valid_optional_identifier?(value), do: valid_identifier?(value)

  defp normalize_location_id(nil), do: nil
  defp normalize_location_id(value) when is_integer(value) and value > 0 and value <= @max_pg_bigint, do: value

  defp normalize_location_id(value) when is_binary(value) do
    if Regex.match?(@safe_location_id, value), do: value, else: :error
  end

  defp normalize_location_id(_value), do: :error

  defp valid_location_id?(nil), do: true

  defp valid_location_id?(value) when is_integer(value), do: value > 0 and value <= @max_pg_bigint

  defp valid_location_id?(value) when is_binary(value), do: Regex.match?(@safe_location_id, value)
  defp valid_location_id?(_value), do: false

  defp issue_sort_key(issue) do
    {
      issue["domain"],
      issue["code"],
      issue["container_type"] || "",
      sortable_id(issue["container_id"]),
      issue["entity_type"],
      sortable_id(issue["entity_id"]),
      issue["source_field"] || "",
      issue["impact"],
      issue["severity"]
    }
  end

  defp sortable_id(nil), do: {0, ""}
  defp sortable_id(value) when is_integer(value), do: {1, value}
  defp sortable_id(value), do: {2, value}

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(_value), do: nil

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
