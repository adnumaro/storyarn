defmodule Storyarn.ProjectTemplates.LegacySnapshotRepair do
  @moduledoc """
  Explicitly repairs the narrow legacy template shape produced before sequence
  resources and runtime-only localization were included in project snapshots.

  Missing sequence semantics cannot be reconstructed. Repair therefore replaces
  each affected sequence in place with an annotation that identifies the lost
  container. Keeping the node slot preserves every connection index and canvas
  position without inventing hierarchy, dimensions, tracks, or visual layers.
  """

  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.SourceContract
  alias Storyarn.ProjectTemplates.Audit

  @max_int32 2_147_483_647
  @max_int64 9_223_372_036_854_775_807
  @legacy_format_version 2
  @sha256_format ~r/\A[0-9a-f]{64}\z/
  @glossary_term_format ~r/\A[^\t\r\n]*\z/u
  @valid_text_statuses ~w(pending draft in_progress review final)
  @valid_vo_statuses ~w(none needed recorded approved)
  @valid_content_roles SourceContract.content_roles()
  @valid_archive_reasons ~w(source_deleted source_field_removed source_not_runtime version_replaced)
  @missing_sequence_error_types MapSet.new([
                                  "missing_sequence_config_snapshot",
                                  "missing_sequence_collection_snapshot"
                                ])
  @required_sequence_errors MapSet.new([
                              "missing_sequence_config_snapshot",
                              "missing_sequence_tracks_snapshot",
                              "missing_sequence_visual_layers_snapshot"
                            ])

  @doc """
  Formats the operator-facing summary for a legacy snapshot repair.

  The report may come from portable bundle metadata, so the fields consumed by
  the Mix and release entrypoints are validated before they are interpolated.
  """
  @spec preview_lines(nil | map()) ::
          {:ok, [String.t()]} | {:error, :invalid_legacy_snapshot_repair_report}
  def preview_lines(nil), do: {:ok, []}

  def preview_lines(%{
        "repaired_sequence_count" => repaired_sequence_count,
        "localization" => %{"removed_count" => removed_count},
        "warning" => warning
      })
      when is_integer(repaired_sequence_count) and repaired_sequence_count >= 0 and is_integer(removed_count) and
             removed_count >= 0 and is_binary(warning) do
    if String.valid?(warning) do
      {:ok,
       [
         "Sequences replaced by recovery notes: #{repaired_sequence_count}",
         "Legacy localization rows removed: #{removed_count}",
         "Warning: #{warning}"
       ]}
    else
      {:error, :invalid_legacy_snapshot_repair_report}
    end
  end

  def preview_lines(_report), do: {:error, :invalid_legacy_snapshot_repair_report}

  @spec repair(map()) :: {:ok, map(), map()} | {:error, term()}
  def repair(snapshot) when is_map(snapshot) do
    with {:ok, targets} <- repair_targets(snapshot),
         :ok <- validate_legacy_snapshot_signature(snapshot, targets),
         :ok <- validate_localization(snapshot["localization"]),
         :ok <- reject_localized_target_sequences(snapshot["localization"], targets),
         {:ok, flows, repaired_sequences} <- repair_flows(snapshot["flows"], targets),
         {:ok, localization, localization_report} <-
           repair_localization(snapshot),
         repaired_snapshot =
           snapshot
           |> Map.put("flows", flows)
           |> Map.put("localization", localization)
           |> update_localized_text_count(localization),
         :ok <- validate_repaired_snapshot(repaired_snapshot) do
      {:ok, repaired_snapshot, repair_report(repaired_sequences, localization_report)}
    end
  end

  def repair(_snapshot), do: {:error, :invalid_legacy_template_snapshot}

  defp repair_targets(snapshot) do
    case Audit.validate_snapshot_integrity(snapshot) do
      :ok ->
        {:error, :legacy_snapshot_repair_not_required}

      {:error, errors} ->
        if repairable_sequence_errors?(errors) do
          {:ok, target_map(errors)}
        else
          {:error, {:unsupported_legacy_template_snapshot, errors}}
        end
    end
  end

  defp repairable_sequence_errors?(errors) when is_list(errors) and errors != [] do
    Enum.all?(errors, &MapSet.member?(@missing_sequence_error_types, &1["type"])) and
      complete_target_error_sets?(errors)
  end

  defp repairable_sequence_errors?(_errors), do: false

  defp complete_target_error_sets?(errors) do
    errors
    |> Enum.group_by(&{&1["flow_id"], &1["node_id"]})
    |> Enum.all?(fn {_target, target_errors} ->
      target_errors
      |> MapSet.new(&normalized_sequence_error_type/1)
      |> MapSet.equal?(@required_sequence_errors)
    end)
  end

  defp normalized_sequence_error_type(%{"type" => "missing_sequence_collection_snapshot", "field" => "sequence_tracks"}),
    do: "missing_sequence_tracks_snapshot"

  defp normalized_sequence_error_type(%{
         "type" => "missing_sequence_collection_snapshot",
         "field" => "sequence_visual_layers"
       }), do: "missing_sequence_visual_layers_snapshot"

  defp normalized_sequence_error_type(error), do: error["type"]

  defp target_map(errors) do
    MapSet.new(errors, &{&1["flow_id"], &1["node_id"]})
  end

  defp validate_legacy_snapshot_signature(%{"format_version" => @legacy_format_version, "flows" => flows}, targets)
       when is_list(flows) do
    with {:ok, flow_ids, node_ids, sequence_targets} <- validate_legacy_flows(flows),
         true <- unique_values?(flow_ids),
         true <- unique_values?(node_ids),
         true <- MapSet.equal?(sequence_targets, targets) do
      :ok
    else
      false -> {:error, :invalid_legacy_template_identity}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_legacy_snapshot_signature(_snapshot, _targets), do: {:error, :unsupported_legacy_template_format}

  defp validate_legacy_flows(flows) do
    Enum.reduce_while(flows, {:ok, [], [], MapSet.new()}, fn flow, {:ok, flow_ids, node_ids, targets} ->
      case validate_legacy_flow(flow) do
        {:ok, flow_id, flow_node_ids, flow_targets} ->
          {:cont, {:ok, [flow_id | flow_ids], flow_node_ids ++ node_ids, MapSet.union(targets, flow_targets)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_legacy_flow(%{
         "id" => flow_id,
         "snapshot" => %{"original_id" => flow_id, "nodes" => nodes, "connections" => connections}
       })
       when is_integer(flow_id) and flow_id > 0 and is_list(nodes) and is_list(connections) do
    with :ok <- validate_legacy_nodes(nodes, flow_id),
         :ok <- validate_connection_indexes(connections, length(nodes), flow_id) do
      node_ids = Enum.map(nodes, & &1["original_id"])

      targets =
        nodes
        |> Enum.filter(&(&1["type"] == "sequence"))
        |> MapSet.new(&{flow_id, &1["original_id"]})

      {:ok, flow_id, node_ids, targets}
    end
  end

  defp validate_legacy_flow(_flow), do: {:error, :invalid_legacy_template_flow}

  defp validate_legacy_nodes(nodes, flow_id) do
    valid? =
      Enum.all?(nodes, fn
        %{"original_id" => node_id, "type" => "sequence"} = node when is_integer(node_id) and node_id > 0 ->
          not Map.has_key?(node, "parent_id") and legacy_sequence_node?(node)

        %{"original_id" => node_id} = node when is_integer(node_id) and node_id > 0 ->
          not Map.has_key?(node, "parent_id")

        _node ->
          false
      end)

    if valid?, do: :ok, else: {:error, {:invalid_legacy_sequence_shape, flow_id}}
  end

  defp validate_connection_indexes(connections, node_count, flow_id) do
    valid? =
      Enum.all?(connections, fn
        %{"source_node_index" => source_index, "target_node_index" => target_index}
        when is_integer(source_index) and is_integer(target_index) ->
          source_index >= 0 and source_index < node_count and target_index >= 0 and target_index < node_count

        _connection ->
          false
      end)

    if valid?, do: :ok, else: {:error, {:invalid_legacy_connection_indexes, flow_id}}
  end

  defp unique_values?(values), do: length(values) == MapSet.size(MapSet.new(values))

  defp repair_flows(flows, targets) when is_list(flows) do
    flows
    |> Enum.reduce_while({:ok, [], []}, fn flow, {:ok, repaired_flows, repaired_sequences} ->
      case repair_flow(flow, targets) do
        {:ok, repaired_flow, flow_repairs} ->
          {:cont, {:ok, [repaired_flow | repaired_flows], flow_repairs ++ repaired_sequences}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, repaired_flows, repaired_sequences} ->
        {:ok, Enum.reverse(repaired_flows), Enum.reverse(repaired_sequences)}

      error ->
        error
    end
  end

  defp repair_flows(_flows, _targets), do: {:error, :invalid_legacy_template_flows}

  defp repair_flow(%{"snapshot" => flow_snapshot} = flow, targets) when is_map(flow_snapshot) do
    flow_id = flow["id"] || flow_snapshot["original_id"]
    flow_targets = Enum.filter(targets, fn {target_flow_id, _node_id} -> target_flow_id == flow_id end)

    if flow_targets == [] do
      {:ok, flow, []}
    else
      repair_targeted_flow(flow, flow_snapshot, flow_id, flow_targets)
    end
  end

  defp repair_flow(_flow, _targets), do: {:error, :invalid_legacy_template_flow}

  defp repair_targeted_flow(flow, flow_snapshot, flow_id, flow_targets) do
    nodes = flow_snapshot["nodes"]
    connections = flow_snapshot["connections"]
    target_ids = MapSet.new(flow_targets, fn {_flow_id, node_id} -> node_id end)

    with true <- is_list(nodes),
         true <- is_list(connections),
         :ok <- require_pre_parent_snapshot(nodes, flow_id),
         {:ok, target_indexes} <- target_indexes(nodes, target_ids, flow_id),
         :ok <- reject_connected_sequences(connections, target_indexes, flow_id) do
      {repaired_nodes, repairs} =
        nodes
        |> Enum.with_index()
        |> Enum.map_reduce([], fn {node, index}, repairs ->
          {repaired_node, repairs} =
            repair_targeted_node(node, index, target_indexes, flow_id, repairs)

          {Map.put(repaired_node, "parent_id", nil), repairs}
        end)

      repaired_flow = put_in(flow, ["snapshot", "nodes"], repaired_nodes)
      {:ok, repaired_flow, repairs}
    else
      false -> {:error, {:invalid_legacy_sequence_flow, flow_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp repair_targeted_node(node, index, target_indexes, flow_id, repairs) do
    if MapSet.member?(target_indexes, index) do
      repaired = recovered_sequence_annotation(node)
      repair = %{"flow_id" => flow_id, "node_id" => node["original_id"], "node_index" => index}
      {repaired, [repair | repairs]}
    else
      {node, repairs}
    end
  end

  defp require_pre_parent_snapshot(nodes, flow_id) do
    if Enum.all?(nodes, &(is_map(&1) and not Map.has_key?(&1, "parent_id"))) do
      :ok
    else
      {:error, {:legacy_sequence_parent_data_present, flow_id}}
    end
  end

  defp target_indexes(nodes, target_ids, flow_id) do
    targets =
      nodes
      |> Enum.with_index()
      |> Enum.filter(fn {node, _index} -> MapSet.member?(target_ids, node["original_id"]) end)

    with true <- length(targets) == MapSet.size(target_ids),
         true <- Enum.all?(targets, fn {node, _index} -> legacy_sequence_node?(node) end) do
      {:ok, MapSet.new(targets, fn {_node, index} -> index end)}
    else
      false -> {:error, {:invalid_legacy_sequence_shape, flow_id}}
    end
  end

  defp legacy_sequence_node?(node) do
    is_map(node) and node["type"] == "sequence" and node["data"] == %{} and
      not Map.has_key?(node, "sequence_config") and
      not Map.has_key?(node, "sequence_tracks") and
      not Map.has_key?(node, "sequence_visual_layers")
  end

  defp reject_connected_sequences(connections, target_indexes, flow_id) do
    connected? =
      Enum.any?(connections, fn
        %{"source_node_index" => source_index, "target_node_index" => target_index} ->
          MapSet.member?(target_indexes, source_index) or MapSet.member?(target_indexes, target_index)

        _connection ->
          true
      end)

    if connected?, do: {:error, {:connected_legacy_sequence, flow_id}}, else: :ok
  end

  defp reject_localized_target_sequences(localization, targets) do
    target_ids = MapSet.new(targets, fn {_flow_id, node_id} -> node_id end)

    localized? =
      localization
      |> localization_texts()
      |> Enum.any?(fn
        %{"source_type" => "flow_node", "source_id" => source_id} ->
          MapSet.member?(target_ids, source_id)

        _text ->
          false
      end)

    if localized?, do: {:error, :localized_legacy_sequence}, else: :ok
  end

  defp localization_texts(nil), do: []
  defp localization_texts(%{"texts" => texts}) when is_list(texts), do: texts
  defp localization_texts(_localization), do: [:invalid]

  defp recovered_sequence_annotation(node) do
    original_id = node["original_id"]

    node
    |> Map.put("type", "annotation")
    |> Map.put("data", %{
      "text" =>
        "Recovered legacy sequence ##{original_id}: its grouping, tracks, and visual layers were not present in the template artifact. Recreate the sequence, then remove this note.",
      "legacy_recovery" => %{
        "original_id" => original_id,
        "original_type" => "sequence"
      }
    })
    |> Map.delete("sequence_config")
    |> Map.delete("sequence_tracks")
    |> Map.delete("sequence_visual_layers")
  end

  defp repair_localization(%{"localization" => nil}), do: {:ok, nil, empty_localization_report()}

  defp repair_localization(
         %{"localization" => %{"languages" => languages, "texts" => texts, "glossary" => glossary} = localization} =
           snapshot
       )
       when is_list(languages) and is_list(texts) and is_list(glossary) do
    with {:ok, indexes} <- localization_indexes(snapshot, languages),
         {:ok, kept, removed} <- classify_localization_texts(texts, indexes) do
      {:ok, Map.put(localization, "texts", kept), localization_report(kept, removed)}
    end
  end

  defp repair_localization(_snapshot), do: {:error, :invalid_legacy_template_localization}

  defp validate_localization(nil), do: :ok

  defp validate_localization(%{"languages" => languages, "texts" => texts, "glossary" => glossary})
       when is_list(languages) and is_list(texts) and is_list(glossary) do
    with true <- valid_languages?(languages),
         locales = MapSet.new(languages, & &1["locale_code"]),
         true <- valid_localization_texts?(texts, locales),
         true <- valid_glossary?(glossary) do
      :ok
    else
      _invalid -> {:error, :invalid_legacy_template_localization}
    end
  end

  defp validate_localization(_localization), do: {:error, :invalid_legacy_template_localization}

  defp valid_languages?(languages) do
    Enum.all?(languages, &valid_language?/1) and
      Enum.count(languages, & &1["is_source"]) <= 1 and
      unique_values?(Enum.map(languages, & &1["locale_code"]))
  end

  defp valid_language?(
         %{"locale_code" => locale_code, "name" => name, "is_source" => is_source, "position" => position} = language
       ) do
    canonical_locale?(locale_code) and
      valid_required_string?(name, 100) and
      is_boolean(is_source) and
      safe_int32?(position) and
      valid_datetime?(language["archived_at"])
  end

  defp valid_language?(_language), do: false

  defp valid_localization_texts?(texts, locales) do
    Enum.all?(texts, &valid_localization_text?(&1, locales)) and
      unique_values?(Enum.map(texts, &{&1["source_type"], &1["source_id"], &1["source_field"], &1["locale_code"]}))
  end

  defp valid_localization_text?(
         %{
           "source_type" => source_type,
           "source_id" => source_id,
           "source_field" => source_field,
           "locale_code" => locale_code
         } = text,
         locales
       ) do
    valid_text_identity?(source_type, source_id, source_field, locale_code, locales) and
      valid_text_content?(text) and
      valid_text_workflow?(text) and
      valid_text_attribution?(text)
  end

  defp valid_localization_text?(_text, _locales), do: false

  defp valid_text_identity?(source_type, source_id, source_field, locale_code, locales) do
    valid_required_string?(source_type, 255) and
      safe_int32_id?(source_id) and
      valid_required_string?(source_field, 255) and
      canonical_locale?(locale_code) and
      MapSet.member?(locales, locale_code)
  end

  defp valid_text_content?(text) do
    valid_optional_string?(text["source_text"]) and
      valid_optional_hash?(text["source_text_hash"]) and
      valid_optional_hash?(text["translated_source_hash"]) and
      valid_optional_string?(text["translated_text"]) and
      valid_optional_word_count?(text["word_count"]) and
      valid_optional_enum?(text["content_role"], @valid_content_roles)
  end

  defp valid_text_workflow?(text) do
    valid_optional_enum?(text["status"], @valid_text_statuses) and
      valid_optional_enum?(text["vo_status"], @valid_vo_statuses) and
      valid_optional_id?(text["vo_asset_id"]) and
      valid_optional_id?(text["speaker_sheet_id"]) and
      valid_optional_boolean?(text["vo_eligible"]) and
      valid_optional_boolean?(text["machine_translated"])
  end

  defp valid_text_attribution?(text) do
    valid_optional_string?(text["translator_notes"]) and
      valid_optional_string?(text["reviewer_notes"]) and
      valid_datetime?(text["last_translated_at"]) and
      valid_datetime?(text["last_reviewed_at"]) and
      valid_optional_id?(text["translated_by_id"]) and
      valid_optional_id?(text["reviewed_by_id"]) and
      valid_datetime?(text["archived_at"]) and
      valid_optional_enum?(text["archive_reason"], @valid_archive_reasons)
  end

  defp valid_glossary?(glossary) do
    Enum.all?(glossary, &valid_glossary_entry?/1) and
      unique_values?(Enum.map(glossary, &{&1["source_term"], &1["source_locale"], &1["target_locale"]}))
  end

  defp valid_glossary_entry?(
         %{"source_term" => source_term, "source_locale" => source_locale, "target_locale" => target_locale} = entry
       ) do
    valid_glossary_source_term?(source_term) and
      valid_glossary_locale?(source_locale) and
      valid_glossary_term?(entry["target_term"]) and
      valid_glossary_locale?(target_locale) and
      valid_optional_string?(entry["context"]) and
      valid_optional_boolean?(entry["do_not_translate"])
  end

  defp valid_glossary_entry?(_entry), do: false

  defp canonical_locale?(locale_code) do
    valid_utf8_string?(locale_code) and
      LocaleCode.valid?(locale_code) and LocaleCode.normalize(locale_code) == locale_code
  end

  defp valid_glossary_locale?(locale_code) do
    valid_utf8_string?(locale_code) and
      LocaleCode.valid?(locale_code) and String.length(locale_code) <= 10
  end

  defp valid_required_string?(value, max_length) when is_binary(value) do
    String.valid?(value) and String.trim(value) != "" and String.length(value) <= max_length
  end

  defp valid_required_string?(_value, _max_length), do: false

  defp valid_optional_string?(nil), do: true
  defp valid_optional_string?(value), do: valid_utf8_string?(value)

  defp valid_optional_hash?(nil), do: true

  defp valid_optional_hash?(value) when is_binary(value) do
    String.valid?(value) and Regex.match?(@sha256_format, value)
  end

  defp valid_optional_hash?(_value), do: false

  defp valid_optional_enum?(nil, _values), do: true
  defp valid_optional_enum?(value, values), do: value in values

  defp valid_optional_boolean?(nil), do: true
  defp valid_optional_boolean?(value), do: is_boolean(value)

  defp valid_optional_id?(nil), do: true
  defp valid_optional_id?(value), do: is_integer(value) and value > 0 and value <= @max_int64

  defp safe_int32_id?(value), do: is_integer(value) and value > 0 and value <= @max_int32

  defp safe_int32?(value) do
    is_integer(value) and value >= -@max_int32 - 1 and value <= @max_int32
  end

  defp valid_optional_word_count?(nil), do: true
  defp valid_optional_word_count?(value), do: is_integer(value) and value >= 0 and value <= @max_int32

  defp valid_datetime?(nil), do: true
  defp valid_datetime?(%DateTime{}), do: true

  defp valid_datetime?(value) when is_binary(value) do
    String.valid?(value) and
      match?({:ok, %DateTime{}, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_datetime?(_value), do: false

  defp valid_glossary_source_term?(value) do
    valid_required_string?(value, 255) and Regex.match?(@glossary_term_format, value)
  end

  defp valid_glossary_term?(nil), do: true

  defp valid_glossary_term?(value) when is_binary(value) do
    String.valid?(value) and
      String.length(value) <= 255 and Regex.match?(@glossary_term_format, value)
  end

  defp valid_glossary_term?(_value), do: false

  defp valid_utf8_string?(value), do: is_binary(value) and String.valid?(value)

  defp classify_localization_texts(texts, indexes) do
    texts
    |> Enum.reduce_while({:ok, [], []}, fn text, {:ok, kept, removed} ->
      case classify_localization_text(text, indexes) do
        :keep -> {:cont, {:ok, [text | kept], removed}}
        :remove -> {:cont, {:ok, kept, [text | removed]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, kept, removed} -> {:ok, Enum.reverse(kept), Enum.reverse(removed)}
      error -> error
    end
  end

  defp classify_localization_text(text, indexes) do
    source_type = text["source_type"]
    source_field = text["source_field"]

    cond do
      not MapSet.member?(indexes.locales, text["locale_code"]) ->
        {:error, {:invalid_legacy_localization_locale, text["locale_code"]}}

      SourceContract.field?(source_type, source_field) ->
        if runtime_localization_source?(text, indexes) do
          :keep
        else
          {:error, {:invalid_runtime_localization_source, source_type, text["source_id"], source_field}}
        end

      legacy_editor_metadata_field?(text, indexes) ->
        :remove

      true ->
        {:error, {:unsupported_legacy_localization_source, source_type, text["source_id"], source_field}}
    end
  end

  defp runtime_localization_source?(
         %{"source_type" => "flow_node", "source_id" => source_id, "source_field" => source_field},
         indexes
       ) do
    case Map.get(indexes.flow_nodes, source_id) do
      %{} = node ->
        SourceContract.localizable_source_field?(
          "flow_node",
          %{type: node["type"], data: node["data"] || %{}, deleted_at: nil},
          source_field
        )

      nil ->
        false
    end
  end

  defp runtime_localization_source?(
         %{"source_type" => "block", "source_id" => source_id, "source_field" => source_field},
         indexes
       ) do
    case Map.get(indexes.blocks, source_id) do
      %{} = block ->
        SourceContract.localizable_source_field?(
          "block",
          %{
            type: block["type"],
            is_constant: block["is_constant"],
            variable_name: block["variable_name"],
            deleted_at: nil
          },
          source_field
        )

      nil ->
        false
    end
  end

  defp runtime_localization_source?(
         %{"source_type" => "sheet", "source_id" => source_id, "source_field" => source_field},
         indexes
       ) do
    Map.has_key?(indexes.sheets, source_id) and
      SourceContract.localizable_source_field?("sheet", %{deleted_at: nil}, source_field)
  end

  defp runtime_localization_source?(_text, _indexes), do: false

  defp legacy_editor_metadata_field?(
         %{"source_type" => "flow", "source_id" => source_id, "source_field" => source_field},
         indexes
       )
       when source_field in ["name", "description"] do
    Map.has_key?(indexes.flows, source_id)
  end

  defp legacy_editor_metadata_field?(
         %{"source_type" => "flow", "source_id" => source_id, "source_field" => source_field},
         indexes
       ) do
    with %{} = flow <- Map.get(indexes.flows, source_id),
         {:ok, connection_id} <- dynamic_field_id(source_field, "connection", "label") do
      snapshot_child?(flow["connections"], connection_id)
    else
      _other -> false
    end
  end

  defp legacy_editor_metadata_field?(
         %{"source_type" => "flow_node", "source_id" => source_id, "source_field" => source_field},
         indexes
       ) do
    with %{} = node <- Map.get(indexes.flow_nodes, source_id),
         {:ok, case_id} <- dynamic_field_id(source_field, "case", "label") do
      snapshot_child?(get_in(node, ["data", "cases"]), case_id)
    else
      _other -> false
    end
  end

  defp legacy_editor_metadata_field?(
         %{"source_type" => "sheet", "source_id" => source_id, "source_field" => "description"},
         indexes
       ) do
    Map.has_key?(indexes.sheets, source_id)
  end

  defp legacy_editor_metadata_field?(%{"source_type" => "block", "source_id" => source_id} = text, indexes) do
    case Map.get(indexes.blocks, source_id) do
      %{} = block -> legacy_block_field?(block, text)
      nil -> false
    end
  end

  defp legacy_editor_metadata_field?(
         %{"source_type" => "scene", "source_id" => source_id, "source_field" => source_field},
         indexes
       ) do
    case Map.get(indexes.scenes, source_id) do
      %{} = scene -> legacy_scene_field?(scene, source_field)
      nil -> false
    end
  end

  defp legacy_editor_metadata_field?(_text, _indexes), do: false

  defp legacy_block_field?(block, %{"source_field" => source_field} = text)
       when source_field in ["config.label", "config.placeholder"] do
    [_config, field] = String.split(source_field, ".")
    legacy_text_matches?(text, get_in(block, ["config", field]))
  end

  defp legacy_block_field?(%{"type" => type} = block, text) when type in ["select", "multi_select"] do
    legacy_option_field?(get_in(block, ["config", "options"]), text)
  end

  defp legacy_block_field?(%{"type" => "table"} = block, text) do
    legacy_table_field?(get_in(block, ["table_data", "columns"]), "table_column", text) or
      legacy_table_field?(get_in(block, ["table_data", "rows"]), "table_row", text)
  end

  defp legacy_block_field?(%{"type" => "gallery"} = block, text) do
    legacy_gallery_field?(block["gallery_images"], text)
  end

  defp legacy_block_field?(_block, _text), do: false

  defp legacy_option_field?(options, %{"source_field" => source_field} = text) when is_list(options) do
    options
    |> Enum.with_index()
    |> Enum.any?(fn
      {%{} = option, index} ->
        field_id = option["key"] || option["value"] || option["label"] || index
        expected_text = option["value"] || option["label"]
        source_field == "config.options.#{field_id}" and legacy_text_matches?(text, expected_text)

      {option, index} when is_binary(option) ->
        source_field == "config.options.#{index}" and legacy_text_matches?(text, option)

      {_option, _index} ->
        false
    end)
  end

  defp legacy_option_field?(_options, _text), do: false

  defp legacy_table_field?(children, prefix, %{"source_field" => source_field} = text) when is_list(children) do
    Regex.match?(~r/^#{prefix}\.[1-9]\d*\.name$/, source_field) and
      Enum.any?(children, fn
        %{"name" => name} -> legacy_text_matches?(text, name)
        _child -> false
      end)
  end

  defp legacy_table_field?(_children, _prefix, _text), do: false

  defp legacy_gallery_field?(images, %{"source_field" => source_field} = text) when is_list(images) do
    Enum.any?(["label", "description"], fn field ->
      with {:ok, image_id} <- dynamic_field_id(source_field, "gallery_image", field),
           %{} = image <- find_snapshot_child(images, image_id) do
        legacy_text_matches?(text, image[field])
      else
        _other -> false
      end
    end)
  end

  defp legacy_gallery_field?(_images, _text), do: false

  defp legacy_text_matches?(text, expected_text) when is_binary(expected_text) and expected_text != "" do
    text["source_text"] == expected_text and text["source_text_hash"] == sha256(expected_text)
  end

  defp legacy_text_matches?(_text, _expected_text), do: false

  defp legacy_scene_field?(_scene, source_field) when source_field in ["name", "description"], do: true

  defp legacy_scene_field?(scene, source_field) do
    scene_dynamic_field?(scene, source_field, "layer", "name", scene["layers"]) or
      scene_dynamic_field?(scene, source_field, "zone", ["name", "tooltip"], scene_zones(scene)) or
      scene_dynamic_field?(scene, source_field, "pin", ["label", "tooltip"], scene_pins(scene)) or
      scene_dynamic_field?(scene, source_field, "annotation", "text", scene_annotations(scene)) or
      scene_dynamic_field?(scene, source_field, "connection", "label", scene["connections"])
  end

  defp scene_dynamic_field?(scene, source_field, prefix, suffixes, children) do
    suffixes = List.wrap(suffixes)

    is_map(scene) and
      Enum.any?(suffixes, fn suffix ->
        case dynamic_field_id(source_field, prefix, suffix) do
          {:ok, child_id} -> snapshot_child?(children, child_id)
          _other -> false
        end
      end)
  end

  defp scene_zones(scene) do
    scene_children(scene, "zones", "orphan_zones")
  end

  defp scene_pins(scene) do
    scene_children(scene, "pins", "orphan_pins")
  end

  defp scene_annotations(scene) do
    scene_children(scene, "annotations", "orphan_annotations")
  end

  defp scene_children(scene, nested_key, orphan_key) do
    nested =
      scene
      |> Map.get("layers")
      |> safe_list()
      |> Enum.flat_map(fn
        %{} = layer -> layer |> Map.get(nested_key) |> safe_list()
        _layer -> []
      end)

    nested ++ safe_list(scene[orphan_key])
  end

  defp dynamic_field_id(source_field, prefix, suffix) do
    parts = String.split(source_field || "", ".")
    expected_suffix = if is_nil(suffix), do: [], else: String.split(suffix, ".")
    prefix_parts = String.split(prefix, ".")

    case parts do
      parts when length(parts) == length(prefix_parts) + 1 + length(expected_suffix) ->
        {actual_prefix, [id | actual_suffix]} = Enum.split(parts, length(prefix_parts))

        if actual_prefix == prefix_parts and actual_suffix == expected_suffix do
          {:ok, id}
        else
          :error
        end

      _parts ->
        :error
    end
  end

  defp snapshot_child?(children, id) when is_list(children) do
    not is_nil(find_snapshot_child(children, id))
  end

  defp snapshot_child?(_children, _id), do: false

  defp find_snapshot_child(children, id) when is_list(children) do
    Enum.find(children, fn child ->
      is_map(child) and to_string(child["original_id"] || child["id"]) == to_string(id)
    end)
  end

  defp find_snapshot_child(_children, _id), do: nil

  defp safe_list(value) when is_list(value), do: value
  defp safe_list(_value), do: []

  defp localization_indexes(snapshot, languages) do
    with {:ok, flow_entries} <- validated_snapshot_entries(snapshot["flows"], :flow),
         {:ok, sheet_entries} <- validated_snapshot_entries(snapshot["sheets"], :sheet),
         {:ok, scene_entries} <- validated_snapshot_entries(snapshot["scenes"], :scene),
         {:ok, flow_nodes} <- nested_entities_by_id(flow_entries, "nodes", :flow_node),
         {:ok, blocks} <- nested_entities_by_id(sheet_entries, "blocks", :block) do
      {:ok,
       %{
         locales: MapSet.new(languages, & &1["locale_code"]),
         flows: entry_snapshots_by_id(flow_entries),
         flow_nodes: flow_nodes,
         sheets: entry_snapshots_by_id(sheet_entries),
         blocks: blocks,
         scenes: entry_snapshots_by_id(scene_entries)
       }}
    end
  end

  defp validated_snapshot_entries(entries, entity_type) when is_list(entries) do
    case collect_snapshot_entry_ids(entries) do
      {:ok, ids} ->
        if unique_values?(ids) do
          {:ok, entries}
        else
          {:error, {:invalid_legacy_snapshot_entities, entity_type}}
        end

      :error ->
        {:error, {:invalid_legacy_snapshot_entities, entity_type}}
    end
  end

  defp validated_snapshot_entries(_entries, entity_type), do: {:error, {:invalid_legacy_snapshot_entities, entity_type}}

  defp collect_snapshot_entry_ids(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn
      %{"id" => id, "snapshot" => %{"original_id" => id}}, {:ok, ids}
      when is_integer(id) and id > 0 ->
        {:cont, {:ok, [id | ids]}}

      _entry, _acc ->
        {:halt, :error}
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      :error -> :error
    end
  end

  defp entry_snapshots_by_id(entries) do
    Map.new(entries, fn entry -> {entry["id"], entry["snapshot"]} end)
  end

  defp nested_entities_by_id(entries, key, entity_type) do
    entities =
      Enum.flat_map(entries, fn entry ->
        entry
        |> get_in(["snapshot", key])
        |> list_or_invalid()
      end)

    ids =
      Enum.map(entities, fn
        %{"original_id" => id} when is_integer(id) and id > 0 -> id
        _entity -> nil
      end)

    if Enum.all?(entities, &is_map/1) and Enum.all?(ids, &is_integer/1) and unique_values?(ids) do
      {:ok, Map.new(entities, &{&1["original_id"], &1})}
    else
      {:error, {:invalid_legacy_snapshot_entities, entity_type}}
    end
  end

  defp list_or_invalid(value) when is_list(value), do: value
  defp list_or_invalid(_value), do: [:invalid]

  defp localization_report(kept, removed) do
    %{
      "kept_count" => length(kept),
      "removed_count" => length(removed),
      "removed_sources" =>
        removed
        |> Enum.group_by(&{&1["source_type"], &1["source_field"]})
        |> Enum.map(fn {{source_type, source_field}, entries} ->
          %{
            "source_type" => source_type,
            "source_field" => source_field,
            "count" => length(entries)
          }
        end)
        |> Enum.sort_by(&{&1["source_type"], &1["source_field"]})
    }
  end

  defp empty_localization_report do
    %{"kept_count" => 0, "removed_count" => 0, "removed_sources" => []}
  end

  defp update_localized_text_count(snapshot, %{"texts" => texts}) when is_list(texts) do
    update_in(snapshot, ["entity_counts"], fn
      counts when is_map(counts) -> Map.put(counts, "localized_texts", length(texts))
      counts -> counts
    end)
  end

  defp update_localized_text_count(snapshot, _localization), do: snapshot

  defp validate_repaired_snapshot(snapshot) do
    case Audit.validate_snapshot_integrity(snapshot) do
      :ok -> :ok
      {:error, errors} -> {:error, {:legacy_snapshot_repair_failed, errors}}
    end
  end

  defp repair_report(repaired_sequences, localization_report) do
    %{
      "status" => "repaired_with_warnings",
      "strategy" => "replace_missing_sequences_with_annotations",
      "repaired_sequence_count" => length(repaired_sequences),
      "repaired_sequences" => repaired_sequences,
      "localization" => localization_report,
      "warning" => "Missing sequence grouping, tracks, and visual layers were unavailable and were not invented."
    }
  end

  defp sha256(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
