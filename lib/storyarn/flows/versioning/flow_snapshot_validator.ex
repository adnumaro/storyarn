defmodule Storyarn.Flows.Versioning.FlowSnapshotValidator do
  @moduledoc false

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.RuntimeKey
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Flows.Versioning.LocaleCode
  alias Storyarn.Flows.Versioning.LocalizationCodec
  alias Storyarn.Flows.Versioning.PlaceholderValidator
  alias Storyarn.Flows.Versioning.SourceContract
  alias Storyarn.Shared.HtmlUtils

  @flow_fields ~w(
    original_id name shortcut description is_main settings scene_id nodes connections
    asset_blob_hashes asset_metadata referenced_sheets localization localization_manifest
  )
  @node_fields ~w(original_id type position_x position_y data parent_id)
  @sequence_config_fields ~w(name width height)
  @sequence_track_fields ~w(original_id kind position asset_id start_time end_time volume)
  @sequence_layer_fields ~w(
    original_id asset_id kind label z_index slot x y width height anchor_x anchor_y fit
    opacity visible
  )
  @connection_fields ~w(
    original_id source_node_index target_node_index source_pin target_pin label
  )
  @localization_fields ~w(
    source_type source_id source_field source_text source_text_hash translated_source_hash
    locale_code translated_text status vo_status vo_asset_id translator_notes reviewer_notes
    speaker_sheet_id word_count machine_translated last_translated_at last_reviewed_at
    translated_by_id reviewed_by_id archived_at archive_reason
  )
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @spec validate(term(), pos_integer()) :: :ok | {:error, term()}
  def validate(snapshot, expected_flow_id) when is_map(snapshot) do
    with :ok <- required_keys(snapshot, @flow_fields, :flow),
         :ok <- validate_root(snapshot, expected_flow_id),
         {:ok, nodes} <- list_field(snapshot, "nodes"),
         {:ok, connections} <- list_field(snapshot, "connections"),
         {:ok, localization} <- list_field(snapshot, "localization"),
         :ok <- LocalizationCodec.validate_manifest(localization, snapshot["localization_manifest"]),
         :ok <- validate_nodes(nodes),
         :ok <- validate_connections(connections, nodes) do
      validate_localization(localization, nodes, snapshot["localization_manifest"]["target_locales"])
    end
  end

  def validate(snapshot, _expected_flow_id), do: {:error, {:invalid_flow_snapshot, :expected_map, snapshot}}

  defp validate_root(snapshot, expected_flow_id) do
    validators = [
      {"name", &nonempty_string?/1},
      {"shortcut", &optional_string?/1},
      {"description", &optional_string?/1},
      {"is_main", &is_boolean/1},
      {"settings", &is_map/1},
      {"scene_id", &optional_positive_integer?/1},
      {"asset_blob_hashes", &is_map/1},
      {"asset_metadata", &is_map/1},
      {"referenced_sheets", &is_map/1},
      {"localization_manifest", &is_map/1}
    ]

    with true <- positive_integer?(snapshot["original_id"]),
         true <- snapshot["original_id"] == expected_flow_id,
         nil <- Enum.find(validators, fn {field, validator} -> not validator.(snapshot[field]) end) do
      :ok
    else
      false -> {:error, {:snapshot_flow_id_mismatch, snapshot["original_id"], expected_flow_id}}
      {field, _validator} -> {:error, {:invalid_snapshot_field, :flow, field, snapshot[field]}}
    end
  end

  defp validate_nodes(nodes) do
    with :ok <- unique_ids(nodes, :node),
         :ok <- each(nodes, &validate_node/1),
         :ok <- dialogue_runtime_ids_unique(nodes),
         :ok <- graph_cardinality(nodes),
         :ok <- sequence_resource_ids(nodes, "sequence_tracks", :sequence_track),
         :ok <- sequence_resource_ids(nodes, "sequence_visual_layers", :sequence_visual_layer) do
      validate_parents(nodes)
    end
  end

  defp graph_cardinality(nodes) do
    entry_count = Enum.count(nodes, &(&1["type"] == "entry"))
    exit_count = Enum.count(nodes, &(&1["type"] == "exit"))

    cond do
      entry_count != 1 -> {:error, {:invalid_snapshot_entry_count, entry_count}}
      exit_count < 1 -> {:error, {:invalid_snapshot_exit_count, exit_count}}
      true -> :ok
    end
  end

  defp validate_node(%{} = node) do
    with :ok <- required_keys(node, @node_fields, :node),
         :ok <- validate_node_fields(node) do
      validate_node_payload(node)
    end
  end

  defp validate_node(node), do: {:error, {:invalid_snapshot_node, node}}

  defp validate_node_fields(node) do
    type = node["type"]
    parent_id = node["parent_id"]
    data = node["data"]

    cond do
      type not in FlowNode.node_types() ->
        {:error, {:invalid_snapshot_node_type, node["original_id"], type}}

      not is_number(node["position_x"]) ->
        {:error, {:invalid_snapshot_field, :node, "position_x", node["position_x"]}}

      not is_number(node["position_y"]) ->
        {:error, {:invalid_snapshot_field, :node, "position_y", node["position_y"]}}

      not is_map(data) ->
        {:error, {:invalid_snapshot_field, :node, "data", data}}

      not optional_positive_integer?(data["audio_asset_id"]) ->
        {:error, {:invalid_snapshot_field, :node, "audio_asset_id", data["audio_asset_id"]}}

      not optional_positive_integer?(parent_id) ->
        {:error, {:invalid_snapshot_node_parent_id, node["original_id"], parent_id}}

      true ->
        :ok
    end
  end

  defp validate_node_payload(%{"original_id" => id, "type" => "exit", "data" => data}), do: validate_exit_target(id, data)

  defp validate_node_payload(%{"original_id" => id, "type" => "dialogue", "data" => data}),
    do: validate_dialogue_runtime_ids(id, data)

  defp validate_node_payload(%{"type" => "sequence"} = node), do: validate_sequence(node)
  defp validate_node_payload(_node), do: :ok

  defp validate_exit_target(node_id, data) do
    exit_mode = data["exit_mode"] || "terminal"
    target_type = data["target_type"]
    target_id = data["target_id"]

    cond do
      is_nil(target_type) and is_nil(target_id) ->
        :ok

      exit_mode != "terminal" ->
        {:error,
         {:invalid_flow_exit_target, node_id, :target_not_allowed_for_exit_mode, exit_mode, target_type, target_id}}

      target_type not in ~w(scene flow) ->
        {:error, {:invalid_flow_exit_target, node_id, :invalid_target_type, target_type, target_id}}

      not positive_integer?(target_id) ->
        {:error, {:invalid_flow_exit_target, node_id, :invalid_target_id, target_type, target_id}}

      true ->
        :ok
    end
  end

  defp validate_dialogue_runtime_ids(node_id, data) do
    responses = if Map.has_key?(data, "responses"), do: data["responses"], else: []

    cond do
      not RuntimeKey.valid_dialogue_id?(data["localization_id"]) ->
        {:error, {:invalid_snapshot_dialogue_localization_id, node_id, data["localization_id"]}}

      not is_list(responses) ->
        {:error, {:invalid_snapshot_dialogue_responses, node_id, responses}}

      true ->
        response_ids = Enum.map(responses, &if(is_map(&1), do: &1["id"]))

        cond do
          not Enum.all?(response_ids, &RuntimeKey.valid_response_id?/1) ->
            {:error, {:invalid_snapshot_dialogue_response_id, node_id, response_ids}}

          length(response_ids) != length(Enum.uniq(response_ids)) ->
            {:error, {:duplicate_snapshot_dialogue_response_id, node_id}}

          true ->
            :ok
        end
    end
  end

  defp dialogue_runtime_ids_unique(nodes) do
    ids =
      for %{"type" => "dialogue", "data" => %{"localization_id" => id}} <- nodes,
          do: id

    if length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :duplicate_snapshot_dialogue_localization_id}
  end

  defp validate_sequence(node) do
    with {:ok, tracks} <- required_sequence_collection(node, "sequence_tracks"),
         {:ok, layers} <- required_sequence_collection(node, "sequence_visual_layers"),
         :ok <- validate_sequence_config(node),
         :ok <- unique_ids(tracks, :sequence_track),
         :ok <- unique_ids(layers, :sequence_visual_layer),
         :ok <- each(tracks, &validate_track/1),
         :ok <- each(layers, &validate_layer/1) do
      kinds = Enum.map(tracks, & &1["kind"])

      if length(kinds) == length(Enum.uniq(kinds)),
        do: :ok,
        else: {:error, {:duplicate_sequence_track_kind, node["original_id"]}}
    end
  end

  defp required_sequence_collection(node, key) do
    case Map.fetch(node, key) do
      {:ok, value} when is_list(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_sequence_snapshot_collection, node["original_id"], key, value}}
      :error -> {:error, {:missing_sequence_snapshot_collection, node["original_id"], key}}
    end
  end

  defp validate_sequence_config(node) do
    case Map.fetch(node, "sequence_config") do
      {:ok, nil} ->
        {:error, {:invalid_sequence_config_snapshot, node["original_id"], nil}}

      {:ok, %{} = config} ->
        with :ok <- required_keys(config, @sequence_config_fields, :sequence_config),
             true <- bounded_nonempty_string?(config["name"], 200),
             true <- is_number(config["width"]),
             true <- is_number(config["height"]) do
          :ok
        else
          false -> {:error, {:invalid_sequence_config_snapshot, node["original_id"], config}}
          {:error, _reason} = error -> error
        end

      {:ok, config} ->
        {:error, {:invalid_sequence_config_snapshot, node["original_id"], config}}

      :error ->
        {:error, {:missing_sequence_config_snapshot, node["original_id"]}}
    end
  end

  defp validate_track(track) when is_map(track) do
    with :ok <- required_keys(track, @sequence_track_fields, :sequence_track),
         true <- track["kind"] in SequenceTrack.kinds(),
         true <- is_integer(track["position"]),
         true <- optional_positive_integer?(track["asset_id"]),
         true <- decimal?(track["start_time"]),
         true <- decimal?(track["end_time"]),
         true <- decimal_range?(track["volume"], 0, 1) do
      :ok
    else
      false -> {:error, {:invalid_sequence_track_snapshot, track}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_track(track), do: {:error, {:invalid_sequence_track_snapshot, track}}

  defp validate_layer(layer) when is_map(layer) do
    with :ok <- required_keys(layer, @sequence_layer_fields, :sequence_visual_layer),
         true <- positive_integer?(layer["asset_id"]),
         true <- layer["kind"] in SequenceVisualLayer.kinds(),
         true <- optional_bounded_string?(layer["label"], 120),
         true <- is_integer(layer["z_index"]),
         true <- layer["slot"] in SequenceVisualLayer.slots(),
         true <- Enum.all?(~w(x y anchor_x anchor_y opacity), &normalized_number?(layer[&1])),
         true <- Enum.all?(~w(width height), &unit_dimension?(layer[&1])),
         true <- layer["fit"] in SequenceVisualLayer.fits(),
         true <- is_boolean(layer["visible"]) do
      :ok
    else
      false -> {:error, {:invalid_sequence_visual_layer_snapshot, layer}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_layer(layer), do: {:error, {:invalid_sequence_visual_layer_snapshot, layer}}

  defp sequence_resource_ids(nodes, key, kind) do
    nodes
    |> Enum.flat_map(fn
      %{"type" => "sequence"} = node -> node[key]
      _node -> []
    end)
    |> unique_ids(kind)
  end

  defp validate_parents(nodes) do
    by_id = Map.new(nodes, &{&1["original_id"], &1})

    with :ok <- each(nodes, &validate_parent(&1, by_id)) do
      if Enum.any?(nodes, &parent_cycle?(&1["original_id"], by_id, MapSet.new())),
        do: {:error, :snapshot_node_parent_cycle},
        else: :ok
    end
  end

  defp validate_parent(%{"parent_id" => nil}, _by_id), do: :ok

  defp validate_parent(%{"original_id" => node_id, "parent_id" => node_id}, _by_id),
    do: {:error, {:invalid_snapshot_node_parent, node_id, node_id, :self}}

  defp validate_parent(%{"original_id" => node_id, "parent_id" => parent_id}, by_id) do
    case by_id[parent_id] do
      %{"type" => "sequence"} -> :ok
      parent -> {:error, {:invalid_snapshot_node_parent, node_id, parent_id, parent}}
    end
  end

  defp parent_cycle?(node_id, by_id, seen) do
    case by_id[node_id] do
      %{"parent_id" => nil} ->
        false

      %{"parent_id" => parent_id} ->
        MapSet.member?(seen, parent_id) or
          parent_cycle?(parent_id, by_id, MapSet.put(seen, node_id))

      nil ->
        true
    end
  end

  defp validate_connections(connections, nodes) do
    with :ok <- unique_ids(connections, :connection),
         :ok <- each(connections, &validate_connection(&1, nodes)) do
      tuples =
        Enum.map(connections, fn connection ->
          {connection["source_node_index"], connection["source_pin"], connection["target_node_index"],
           connection["target_pin"]}
        end)

      if length(tuples) == length(Enum.uniq(tuples)),
        do: :ok,
        else: {:error, :duplicate_snapshot_connection}
    end
  end

  defp validate_connection(connection, nodes) when is_map(connection) do
    with :ok <- required_keys(connection, @connection_fields, :connection),
         :ok <- validate_connection_indexes(connection, length(nodes)),
         :ok <- validate_connection_node_types(connection, nodes) do
      validate_connection_fields(connection)
    end
  end

  defp validate_connection(connection, _nodes), do: {:error, {:invalid_snapshot_connection, connection}}

  defp validate_connection_indexes(connection, node_count) do
    source_index = connection["source_node_index"]
    target_index = connection["target_node_index"]
    connection_id = connection["original_id"]

    cond do
      not valid_index?(source_index, node_count) ->
        {:error, {:invalid_snapshot_connection_endpoint, connection_id, :source, source_index}}

      not valid_index?(target_index, node_count) ->
        {:error, {:invalid_snapshot_connection_endpoint, connection_id, :target, target_index}}

      source_index == target_index ->
        {:error, {:invalid_snapshot_self_connection, connection_id, source_index}}

      true ->
        :ok
    end
  end

  defp validate_connection_node_types(connection, nodes) do
    source_type = Enum.at(nodes, connection["source_node_index"])["type"]
    target_type = Enum.at(nodes, connection["target_node_index"])["type"]

    cond do
      source_type == "sequence" ->
        {:error, {:invalid_snapshot_sequence_connection, connection["original_id"], :source}}

      target_type == "sequence" ->
        {:error, {:invalid_snapshot_sequence_connection, connection["original_id"], :target}}

      true ->
        :ok
    end
  end

  defp validate_connection_fields(connection) do
    source_pin = connection["source_pin"]
    target_pin = connection["target_pin"]
    label = connection["label"]

    cond do
      not bounded_nonempty_string?(source_pin, 100) ->
        {:error, {:invalid_snapshot_connection_pin, connection["original_id"], :source, source_pin}}

      not bounded_nonempty_string?(target_pin, 100) ->
        {:error, {:invalid_snapshot_connection_pin, connection["original_id"], :target, target_pin}}

      not optional_bounded_string?(label, 200) ->
        {:error, {:invalid_snapshot_connection_label, connection["original_id"], label}}

      true ->
        :ok
    end
  end

  defp validate_localization(rows, nodes, target_locales) do
    nodes_by_id = Map.new(nodes, &{&1["original_id"], &1})
    sources = localization_sources(nodes)

    with true <- is_list(target_locales),
         :ok <- each(rows, &validate_localization_row(&1, nodes_by_id, sources)),
         :ok <- unique_localization_rows(rows),
         {:ok, target_locale_set} <- validate_localization_locales(rows, target_locales) do
      expected =
        for {source_key, _source} <- sources,
            locale <- target_locale_set,
            into: MapSet.new(),
            do: {source_key, locale}

      actual =
        MapSet.new(rows, fn row ->
          {{row["source_id"], row["source_field"]}, row["locale_code"]}
        end)

      if actual == expected,
        do: :ok,
        else: {:error, {:incomplete_flow_localization_snapshot, %{expected: expected, actual: actual}}}
    else
      false -> {:error, {:invalid_localization_target_locales, target_locales}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_localization_row(row, nodes_by_id, sources) when is_map(row) do
    source_node = nodes_by_id[row["source_id"]]
    source = sources[{row["source_id"], row["source_field"]}]

    with :ok <- exact_keys(row, @localization_fields, :localization),
         true <- row["source_type"] == "flow_node",
         true <- positive_integer?(row["source_id"]),
         true <- is_map(source_node) and is_map(source),
         true <- SourceContract.field?(row["source_type"], row["source_field"]),
         true <-
           SourceContract.localizable_source_field?(
             "flow_node",
             %{type: source_node["type"], data: source_node["data"], deleted_at: nil},
             row["source_field"]
           ),
         true <- is_binary(row["source_text"]),
         true <- sha256?(row["source_text_hash"]),
         true <- optional_sha256?(row["translated_source_hash"]),
         true <- LocaleCode.valid?(row["locale_code"]),
         true <- row["locale_code"] == LocaleCode.normalize(row["locale_code"]),
         true <- optional_string?(row["translated_text"]),
         true <- row["status"] in ~w(pending draft in_progress review final),
         true <- row["vo_status"] in ~w(none needed recorded approved),
         true <- optional_positive_integer?(row["vo_asset_id"]),
         true <- optional_string?(row["translator_notes"]),
         true <- optional_string?(row["reviewer_notes"]),
         true <- optional_positive_integer?(row["speaker_sheet_id"]),
         true <- is_integer(row["word_count"]) and row["word_count"] >= 0,
         true <- is_boolean(row["machine_translated"]),
         true <- datetime?(row["last_translated_at"]),
         true <- datetime?(row["last_reviewed_at"]),
         true <- optional_positive_integer?(row["translated_by_id"]),
         true <- optional_positive_integer?(row["reviewed_by_id"]),
         true <- datetime?(row["archived_at"]),
         true <- optional_string?(row["archive_reason"]) do
      validate_localization_semantics(row, source)
    else
      false -> {:error, {:invalid_flow_localization_snapshot, row}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_localization_row(row, _nodes_by_id, _sources), do: {:error, {:invalid_flow_localization_snapshot, row}}

  defp validate_localization_semantics(row, source) do
    expected_hash = source_hash(source.text)

    with :ok <- validate_localization_source_text(row, source.text),
         :ok <- validate_localization_source_hash(row, expected_hash),
         :ok <- validate_localization_word_count(row, source.text),
         :ok <- validate_localization_speaker(row, source.speaker_sheet_id),
         :ok <- validate_active_localization_state(row),
         :ok <- validate_localization_translation_state(row),
         :ok <- validate_placeholders(row) do
      validate_localization_voiceover_state(row, source.metadata)
    end
  end

  defp validate_localization_source_text(row, expected) do
    if row["source_text"] == expected,
      do: :ok,
      else: {:error, {:localization_source_text_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_localization_source_hash(row, expected) do
    if row["source_text_hash"] == expected,
      do: :ok,
      else: {:error, {:localization_source_text_hash_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_localization_word_count(row, source_text) do
    if row["word_count"] == HtmlUtils.word_count(source_text),
      do: :ok,
      else: {:error, {:localization_word_count_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_localization_speaker(row, expected) do
    if row["speaker_sheet_id"] == expected,
      do: :ok,
      else: {:error, {:localization_speaker_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_active_localization_state(row) do
    if is_nil(row["archived_at"]) and is_nil(row["archive_reason"]) do
      :ok
    else
      {:error, {:invalid_active_localization_archive_state, row["source_id"], row["source_field"], row["locale_code"]}}
    end
  end

  defp validate_localization_translation_state(row) do
    if coherent_translation?(row),
      do: :ok,
      else: {:error, {:invalid_localization_translation_state, row["source_id"], row["source_field"], row["locale_code"]}}
  end

  defp coherent_translation?(row) do
    translated? = present_string?(row["translated_text"])

    Enum.all?([
      valid_translated_text?(row["translated_text"]),
      coherent_translated_hash?(row["translated_source_hash"], translated?),
      coherent_machine_translation?(row["machine_translated"], translated?),
      coherent_final_translation?(row, translated?)
    ])
  end

  defp valid_translated_text?(nil), do: true
  defp valid_translated_text?(text), do: present_string?(text)

  defp coherent_translated_hash?(nil, false), do: true
  defp coherent_translated_hash?(hash, true), do: sha256?(hash)
  defp coherent_translated_hash?(_hash, _translated?), do: false

  defp coherent_machine_translation?(false, _translated?), do: true
  defp coherent_machine_translation?(_machine_translated, translated?), do: translated?

  defp coherent_final_translation?(%{"status" => status}, _translated?) when status != "final", do: true

  defp coherent_final_translation?(row, translated?) do
    translated? and row["translated_source_hash"] == row["source_text_hash"]
  end

  defp validate_placeholders(%{"translated_text" => translated_text} = row) when is_binary(translated_text) do
    case PlaceholderValidator.validate(row["source_text"], translated_text) do
      :ok ->
        :ok

      {:error, details} ->
        {:error, {:invalid_localization_placeholders, row["source_id"], row["source_field"], row["locale_code"], details}}
    end
  end

  defp validate_placeholders(_row), do: :ok

  defp coherent_voiceover?(row, %{vo_eligible: false}), do: row["vo_status"] == "none" and is_nil(row["vo_asset_id"])

  defp coherent_voiceover?(row, %{vo_eligible: true}),
    do: row["vo_status"] not in ~w(recorded approved) or positive_integer?(row["vo_asset_id"])

  defp validate_localization_voiceover_state(row, metadata) do
    if coherent_voiceover?(row, metadata),
      do: :ok,
      else: {:error, {:invalid_localization_voiceover_state, row["source_id"], row["source_field"], row["locale_code"]}}
  end

  defp validate_localization_locales(rows, target_locales) do
    target_locale_set = MapSet.new(target_locales)

    case Enum.find(rows, fn row -> not MapSet.member?(target_locale_set, row["locale_code"]) end) do
      nil ->
        {:ok, target_locale_set}

      row ->
        {:error, {:localization_locale_outside_snapshot, row["source_id"], row["source_field"], row["locale_code"]}}
    end
  end

  defp unique_localization_rows(rows) do
    keys = Enum.map(rows, &{&1["source_id"], &1["source_field"], &1["locale_code"]})
    if length(keys) == length(Enum.uniq(keys)), do: :ok, else: {:error, :duplicate_flow_localization_snapshot}
  end

  defp localization_sources(nodes) do
    Enum.reduce(nodes, %{}, fn node, sources ->
      Enum.reduce(node_sources(node), sources, fn {key, source}, acc -> Map.put(acc, key, source) end)
    end)
  end

  defp node_sources(%{"original_id" => node_id, "type" => "dialogue", "data" => data}) when is_map(data) do
    speaker_id = data["speaker_sheet_id"]

    []
    |> add_source(node_id, "text", data["text"], speaker_id)
    |> add_source(node_id, "stage_directions", data["stage_directions"], nil)
    |> add_source(node_id, "menu_text", data["menu_text"], nil)
    |> add_response_sources(node_id, data["responses"], speaker_id)
  end

  defp node_sources(%{"original_id" => node_id, "type" => "exit", "data" => data}) when is_map(data),
    do: add_source([], node_id, "label", data["label"], nil)

  defp node_sources(_node), do: []

  defp add_response_sources(sources, node_id, responses, speaker_id) when is_list(responses) do
    Enum.reduce(responses, sources, fn
      %{"id" => response_id, "text" => text}, acc when is_binary(response_id) ->
        add_source(acc, node_id, "response.#{response_id}.text", text, speaker_id)

      _response, acc ->
        acc
    end)
  end

  defp add_response_sources(sources, _node_id, _responses, _speaker_id), do: sources

  defp add_source(sources, node_id, field, text, speaker_id) when is_binary(text) do
    if HtmlUtils.strip_html(text) == "" do
      sources
    else
      [
        {{node_id, field},
         %{
           text: text,
           speaker_sheet_id: speaker_id,
           metadata: SourceContract.field_metadata("flow_node", field)
         }}
        | sources
      ]
    end
  end

  defp add_source(sources, _node_id, _field, _text, _speaker_id), do: sources

  defp unique_ids(entries, kind) when is_list(entries) do
    case Enum.find(entries, fn entry ->
           not is_map(entry) or not positive_integer?(entry["original_id"])
         end) do
      nil ->
        ids = Enum.map(entries, & &1["original_id"])

        if length(ids) == length(Enum.uniq(ids)),
          do: :ok,
          else: {:error, {:duplicate_snapshot_original_id, kind}}

      invalid ->
        {:error, {:invalid_snapshot_original_id, kind, invalid}}
    end
  end

  defp required_keys(map, keys, kind) when is_map(map) do
    missing = Enum.reject(keys, &Map.has_key?(map, &1))
    if missing == [], do: :ok, else: {:error, {:missing_snapshot_fields, kind, missing}}
  end

  defp required_keys(value, _keys, kind), do: {:error, {:invalid_snapshot_payload, kind, value}}

  defp exact_keys(map, keys, kind) do
    expected = MapSet.new(keys)
    actual = MapSet.new(Map.keys(map))

    if expected == actual,
      do: :ok,
      else: {:error, {:invalid_snapshot_fields, kind, %{expected: expected, actual: actual}}}
  end

  defp list_field(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_list(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_flow_snapshot_collection, key, value}}
      :error -> {:error, {:missing_snapshot_fields, key}}
    end
  end

  defp each(items, validator) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case validator.(item) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp decimal?(nil), do: true

  defp decimal?(value) when is_binary(value) do
    match?({_decimal, ""}, Decimal.parse(value))
  end

  defp decimal?(_value), do: false

  defp decimal_range?(value, minimum, maximum)
  defp decimal_range?(nil, _minimum, _maximum), do: true

  defp decimal_range?(value, minimum, maximum) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} ->
        Decimal.compare(decimal, minimum) in [:eq, :gt] and
          Decimal.compare(decimal, maximum) in [:eq, :lt]

      _invalid ->
        false
    end
  end

  defp decimal_range?(_value, _minimum, _maximum), do: false

  defp normalized_number?(value), do: is_number(value) and value >= 0 and value <= 1
  defp unit_dimension?(value), do: is_number(value) and value > 0 and value <= 1

  defp datetime?(nil), do: true
  defp datetime?(%DateTime{}), do: true

  defp datetime?(value) when is_binary(value), do: match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))

  defp datetime?(_value), do: false

  defp source_hash(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  defp sha256?(value) when is_binary(value), do: Regex.match?(@sha256_regex, value)
  defp sha256?(_value), do: false
  defp optional_sha256?(nil), do: true
  defp optional_sha256?(value), do: sha256?(value)
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp optional_positive_integer?(nil), do: true
  defp optional_positive_integer?(value), do: positive_integer?(value)
  defp optional_string?(value), do: is_nil(value) or is_binary(value)
  defp nonempty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp bounded_nonempty_string?(value, max_length), do: nonempty_string?(value) and String.length(value) <= max_length

  defp optional_bounded_string?(nil, _max_length), do: true

  defp optional_bounded_string?(value, max_length), do: is_binary(value) and String.length(value) <= max_length

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp valid_index?(value, length), do: is_integer(value) and value >= 0 and value < length
end
