defmodule Storyarn.Projects.Imports.Parsers.Yarn.ReviewDecisions do
  @moduledoc false

  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.Parsers.Yarn.Expression
  alias Storyarn.Projects.Imports.Parsers.Yarn.SpeakerClassifier
  alias Storyarn.Projects.Imports.Parsers.Yarn.SpeakerSheets

  @parser_version "5"
  @speaker_metadata_keys ~w(
    import_yarn_inherited_speaker
    import_yarn_speaker
    import_yarn_literal_text
    import_yarn_literal_source_text
    import_yarn_source_text
  )
  @direct_actions ~w(create_sheet preserve_literal)
  @actions @direct_actions ++ ["map_to_sheet"]

  @doc false
  @spec put_allowed_actions(map()) :: map()
  def put_allowed_actions(%{"speaker_decisions" => decisions} = review) when is_list(decisions) do
    Map.put(
      review,
      "speaker_decisions",
      Enum.map(decisions, fn
        %{"reasons" => reasons} = decision when is_list(reasons) ->
          Map.put(decision, "allowed_actions", allowed_actions(reasons))

        decision ->
          decision
      end)
    )
  end

  def put_allowed_actions(review), do: review

  @doc false
  @spec allowed_actions([String.t()]) :: [String.t()]
  def allowed_actions(reasons) when is_list(reasons) do
    if "dynamic_speaker_expression" in reasons,
      do: ["preserve_literal"],
      else: @actions
  end

  @spec apply(ImportPlan.t(), boolean(), term()) ::
          {:ok, ImportPlan.t()}
          | {:error,
             :invalid_import_review
             | :invalid_import_review_selection
             | :import_review_required
             | :import_review_too_large}
  def apply(
        %ImportPlan{format: :yarn, parser_version: parser_version, data: data} = plan,
        acknowledged?,
        selected_decisions
      )
      when parser_version == @parser_version and is_map(data) do
    with {:ok, review} <- validate_review(data["import_review"]),
         :ok <- require_acknowledgement(review.acknowledgement_required?, acknowledged?),
         {:ok, selected_actions} <-
           validate_selected_decisions(
             review.entries,
             review.alias_pairs,
             selected_decisions
           ),
         :ok <- validate_plan_occurrences(data, review.entries),
         {:ok, resolved_data} <-
           apply_to_data(data, data["import_review"], review.entries, selected_actions) do
      {:ok, %{plan | data: resolved_data}}
    end
  end

  def apply(%ImportPlan{format: :yarn}, _acknowledged?, _selected_decisions), do: {:error, :invalid_import_review}

  def apply(%ImportPlan{} = plan, _acknowledged?, _selected_decisions), do: {:ok, plan}

  @doc false
  @spec save_draft(ImportPlan.t(), term()) ::
          {:ok, ImportPlan.t()}
          | {:error,
             :invalid_import_review
             | :invalid_import_review_selection
             | :import_review_too_large}
  def save_draft(%ImportPlan{format: :yarn, parser_version: @parser_version, data: data} = plan, selected_decisions)
      when is_map(data) do
    with {:ok, review} <- validate_review(data["import_review"]),
         {:ok, decisions} <-
           validate_partial_decisions(review.entries, review.alias_pairs, selected_decisions),
         :ok <- validate_plan_occurrences(data, review.entries) do
      draft = %{
        "version" => 1,
        "decisions" => serialize_decisions(decisions),
        "decision_fingerprint" => decision_fingerprint(decisions)
      }

      {:ok, %{plan | data: data |> Map.put("import_review_draft", draft) |> Map.delete("import_review_resolution")}}
    end
  end

  def save_draft(%ImportPlan{format: :yarn}, _selected_decisions), do: {:error, :invalid_import_review}

  def save_draft(%ImportPlan{} = plan, _selected_decisions), do: {:ok, plan}

  @doc false
  @spec confirmation_fingerprint(ImportPlan.t()) ::
          {:ok, String.t()} | {:error, :invalid_import_review}
  def confirmation_fingerprint(
        %ImportPlan{
          format: :yarn,
          parser_version: @parser_version,
          data: %{
            "import_review_resolution" => %{
              "version" => 2,
              "decision_fingerprint" => fingerprint,
              "decisions" => decisions
            }
          }
        } = plan
      )
      when is_binary(fingerprint) and is_list(decisions) do
    if resolved?(plan), do: {:ok, fingerprint}, else: {:error, :invalid_import_review}
  end

  def confirmation_fingerprint(%ImportPlan{format: :yarn} = plan) do
    if resolved?(plan),
      do: {:ok, "not-required"},
      else: {:error, :invalid_import_review}
  end

  def confirmation_fingerprint(%ImportPlan{}), do: {:ok, "not-required"}

  @doc false
  @spec confirm(ImportPlan.t(), term()) ::
          :ok | {:error, :invalid_import_review | :invalid_import_review_selection}
  def confirm(%ImportPlan{format: :yarn} = plan, supplied_fingerprint) do
    case confirmation_fingerprint(plan) do
      {:ok, "not-required"} when supplied_fingerprint in [nil, "not-required"] ->
        :ok

      {:ok, expected} when is_binary(supplied_fingerprint) and supplied_fingerprint == expected ->
        :ok

      {:ok, _expected} ->
        {:error, :invalid_import_review_selection}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def confirm(%ImportPlan{}, _supplied_fingerprint), do: :ok

  @spec validate(ImportPlan.t()) ::
          :ok | {:error, :invalid_import_review | :import_review_too_large}
  def validate(
        %ImportPlan{
          format: :yarn,
          parser_version: @parser_version,
          data: %{"import_review_resolution" => %{"version" => 2}}
        } = plan
      ) do
    if resolved?(plan), do: :ok, else: {:error, :invalid_import_review}
  end

  def validate(%ImportPlan{
        format: :yarn,
        parser_version: @parser_version,
        data: %{"import_review" => review_data} = data
      }) do
    with {:ok, review} <- validate_review(review_data) do
      validate_plan_occurrences(data, review.entries)
    end
  end

  def validate(%ImportPlan{format: :yarn}), do: {:error, :invalid_import_review}
  def validate(%ImportPlan{}), do: :ok

  @spec resolved?(ImportPlan.t()) :: boolean()
  def resolved?(
        %ImportPlan{
          format: :yarn,
          parser_version: @parser_version,
          data: %{
            "import_review" => review_data,
            "import_review_resolution" => %{
              "version" => 2,
              "decision_fingerprint" => stored_fingerprint,
              "decisions" => stored_decisions
            }
          }
        } = plan
      )
      when is_binary(stored_fingerprint) and is_list(stored_decisions) do
    with {:ok, review} <- validate_review(review_data),
         {:ok, selected_actions} <-
           validate_selected_decisions(review.entries, review.alias_pairs, stored_decisions),
         true <- decision_fingerprint(selected_actions) == stored_fingerprint,
         :ok <- validate_plan_occurrences(plan.data, review.entries) do
      true
    else
      _invalid_resolution -> false
    end
  end

  def resolved?(%ImportPlan{
        format: :yarn,
        parser_version: @parser_version,
        data: %{"import_review" => review_data} = data
      }) do
    with {:ok,
          %{
            entries: [],
            alias_pairs: alias_pairs,
            acknowledgement_required?: false
          }} <- validate_review(review_data),
         true <- MapSet.size(alias_pairs) == 0,
         true <- speaker_occurrences(data) == %{} do
      true
    else
      _review_required -> false
    end
  end

  def resolved?(%ImportPlan{format: :yarn}), do: false
  def resolved?(%ImportPlan{}), do: true

  defp validate_review(review) when is_map(review) do
    with {:ok, entries} <- fetch_list(review, "speaker_decisions"),
         {:ok, _variable_count} <- fetch_non_negative_integer(review, "variable_count"),
         {:ok, decision_count} <- fetch_non_negative_integer(review, "speaker_decision_count"),
         :ok <- ensure_not_truncated(review, "speaker_decisions_truncated"),
         true <- length(entries) == decision_count,
         {:ok, aliases} <- fetch_list(review, "possible_speaker_aliases"),
         {:ok, alias_count} <- fetch_non_negative_integer(review, "possible_speaker_alias_count"),
         :ok <- ensure_not_truncated(review, "possible_speaker_aliases_truncated"),
         true <- length(aliases) == alias_count,
         {:ok, alias_pairs} <- validate_aliases(aliases),
         {:ok, compatibility_warning_count} <-
           fetch_non_negative_integer(review, "compatibility_warning_count"),
         {:ok, compatibility_warning_counts_by_code} <-
           validate_compatibility_warning_counts(
             review["compatibility_warning_counts_by_code"],
             compatibility_warning_count
           ),
         {:ok, required?} <- fetch_boolean(review, "requires_acknowledgement"),
         true <-
           required? ==
             (decision_count > 0 or alias_count > 0 or
                compatibility_warning_count > 0),
         {:ok, validated_entries} <- validate_review_entries(entries),
         :ok <- validate_suggested_counts(review, validated_entries),
         :ok <- validate_alias_members(alias_pairs, validated_entries) do
      {:ok,
       %{
         entries: validated_entries,
         alias_pairs: alias_pairs,
         acknowledgement_required?: required?,
         compatibility_warning_count: compatibility_warning_count,
         compatibility_warning_counts_by_code: compatibility_warning_counts_by_code
       }}
    else
      false -> {:error, :invalid_import_review}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_review(_review), do: {:error, :invalid_import_review}

  defp ensure_not_truncated(review, key) do
    case Map.fetch(review, key) do
      {:ok, false} -> :ok
      {:ok, true} -> {:error, :import_review_too_large}
      _missing_or_invalid -> {:error, :invalid_import_review}
    end
  end

  defp fetch_list(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_list(value) -> {:ok, value}
      _missing_or_invalid -> {:error, :invalid_import_review}
    end
  end

  defp fetch_non_negative_integer(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) and value >= 0 -> {:ok, value}
      _missing_or_invalid -> {:error, :invalid_import_review}
    end
  end

  defp fetch_boolean(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_boolean(value) -> {:ok, value}
      _missing_or_invalid -> {:error, :invalid_import_review}
    end
  end

  defp validate_compatibility_warning_counts(counts, expected_count) when is_map(counts) and map_size(counts) <= 1_000 do
    valid? =
      Enum.all?(counts, fn {code, count} ->
        is_binary(code) and code != "" and String.length(code) <= 100 and
          is_integer(count) and count > 0
      end)

    if valid? and Enum.sum(Map.values(counts)) == expected_count,
      do: {:ok, counts},
      else: {:error, :invalid_import_review}
  end

  defp validate_compatibility_warning_counts(_counts, _expected_count), do: {:error, :invalid_import_review}

  defp validate_alias_members(alias_pairs, validated_entries) do
    speakers = MapSet.new(validated_entries, & &1.speaker)

    if Enum.all?(alias_pairs, fn {left, right} ->
         MapSet.member?(speakers, left) and MapSet.member?(speakers, right)
       end),
       do: :ok,
       else: {:error, :invalid_import_review}
  end

  defp validate_review_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, [], MapSet.new()}, &accumulate_review_entry/2)
    |> case do
      {:ok, validated, _seen} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  defp accumulate_review_entry(entry, {:ok, validated, seen}) do
    with {:ok, %{speaker: speaker} = normalized} <- validate_review_entry(entry),
         false <- MapSet.member?(seen, speaker) do
      {:cont, {:ok, [normalized | validated], MapSet.put(seen, speaker)}}
    else
      true -> {:halt, {:error, :invalid_import_review}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp validate_review_entry(
         %{
           "speaker" => speaker,
           "suggested_action" => suggested_action,
           "occurrences" => occurrences,
           "confidence" => confidence,
           "reasons" => reasons
         } = entry
       ) do
    expected_allowed_actions = allowed_actions(reasons)
    serialized_allowed_actions = Map.get(entry, "allowed_actions", expected_allowed_actions)

    if valid_review_entry_fields?(speaker, suggested_action, occurrences, confidence, reasons) and
         serialized_allowed_actions == expected_allowed_actions do
      {:ok,
       %{
         speaker: speaker,
         suggested_action: suggested_action,
         occurrences: occurrences,
         allowed_actions: expected_allowed_actions
       }}
    else
      {:error, :invalid_import_review}
    end
  end

  defp validate_review_entry(_entry), do: {:error, :invalid_import_review}

  defp valid_review_entry_fields?(speaker, suggested_action, occurrences, confidence, reasons) do
    non_empty_binary?(speaker) and
      suggested_action in @actions and
      positive_integer?(occurrences) and
      confidence in ~w(high medium low) and
      valid_reasons?(reasons)
  end

  defp valid_reasons?([_first | _rest] = reasons), do: Enum.all?(reasons, &non_empty_binary?/1)
  defp valid_reasons?(_reasons), do: false

  defp validate_aliases(aliases) do
    aliases
    |> Enum.reduce_while({:ok, MapSet.new()}, &accumulate_alias/2)
    |> case do
      {:ok, seen} -> {:ok, seen}
      error -> error
    end
  end

  defp accumulate_alias(alias_review, {:ok, seen}) do
    with {:ok, pair} <- validate_alias(alias_review),
         false <- MapSet.member?(seen, pair) do
      {:cont, {:ok, MapSet.put(seen, pair)}}
    else
      _invalid_or_duplicate -> {:halt, {:error, :invalid_import_review}}
    end
  end

  defp validate_alias(%{
         "left" => left,
         "left_occurrences" => left_occurrences,
         "right" => right,
         "right_occurrences" => right_occurrences,
         "more_frequent" => more_frequent,
         "less_frequent" => less_frequent,
         "evidence" => evidence,
         "decision" => "review"
       }) do
    if valid_alias_fields?(
         left,
         left_occurrences,
         right,
         right_occurrences,
         more_frequent,
         less_frequent,
         evidence
       ) do
      {:ok, [left, right] |> Enum.sort() |> List.to_tuple()}
    else
      :error
    end
  end

  defp validate_alias(_alias_review), do: :error

  defp valid_alias_fields?(left, left_occurrences, right, right_occurrences, more_frequent, less_frequent, evidence) do
    names = MapSet.new([left, right])

    valid_alias_names?(left, right) and
      positive_integer?(left_occurrences) and
      positive_integer?(right_occurrences) and
      valid_alias_order?(more_frequent, less_frequent, names) and
      non_empty_binary?(evidence)
  end

  defp valid_alias_names?(left, right) do
    non_empty_binary?(left) and non_empty_binary?(right) and left != right
  end

  defp valid_alias_order?(more_frequent, less_frequent, names) do
    is_binary(more_frequent) and
      is_binary(less_frequent) and
      MapSet.new([more_frequent, less_frequent]) == names
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_empty_binary?(value), do: is_binary(value) and String.trim(value) != ""

  defp validate_suggested_counts(review, entries) do
    with {:ok, sheet_count} <- fetch_non_negative_integer(review, "sheet_speaker_count"),
         {:ok, preserved_count} <- fetch_non_negative_integer(review, "preserved_channel_count"),
         true <- sheet_count + preserved_count == length(entries),
         true <- Enum.count(entries, &(&1.suggested_action == "create_sheet")) == sheet_count,
         true <- Enum.count(entries, &(&1.suggested_action == "preserve_literal")) == preserved_count do
      :ok
    else
      _invalid -> {:error, :invalid_import_review}
    end
  end

  defp require_acknowledgement(false, acknowledged?) when is_boolean(acknowledged?), do: :ok
  defp require_acknowledgement(true, true), do: :ok
  defp require_acknowledgement(_required?, _acknowledged?), do: {:error, :import_review_required}

  defp validate_selected_decisions(review_entries, alias_pairs, selected_decisions) when is_list(selected_decisions) do
    expected = MapSet.new(review_entries, & &1.speaker)

    with {:ok, decisions} <- parse_selected_decisions(selected_decisions),
         true <- MapSet.new(Map.keys(decisions)) == expected,
         :ok <- validate_entry_action_constraints(review_entries, decisions),
         :ok <- validate_complete_alias_mappings(decisions, alias_pairs) do
      {:ok, decisions}
    else
      false -> {:error, :import_review_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_selected_decisions([], _alias_pairs, nil), do: {:ok, %{}}

  defp validate_selected_decisions(_review_entries, _alias_pairs, _selected_decisions),
    do: {:error, :import_review_required}

  defp validate_partial_decisions(review_entries, alias_pairs, selected_decisions) when is_list(selected_decisions) do
    expected = MapSet.new(review_entries, & &1.speaker)

    with {:ok, decisions} <- parse_selected_decisions(selected_decisions),
         true <- MapSet.subset?(MapSet.new(Map.keys(decisions)), expected),
         :ok <- validate_entry_action_constraints(review_entries, decisions),
         :ok <- validate_partial_alias_mappings(decisions, alias_pairs, expected) do
      {:ok, decisions}
    else
      false -> {:error, :invalid_import_review_selection}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_partial_decisions(_review_entries, _alias_pairs, _selected_decisions),
    do: {:error, :invalid_import_review_selection}

  defp parse_selected_decisions(selected_decisions) do
    Enum.reduce_while(selected_decisions, {:ok, %{}}, &accumulate_selected_decision/2)
  end

  defp validate_entry_action_constraints(review_entries, decisions) do
    allowed_actions = Map.new(review_entries, &{&1.speaker, &1.allowed_actions})

    if Enum.all?(decisions, fn {speaker, decision} ->
         decision.action in Map.fetch!(allowed_actions, speaker)
       end) do
      :ok
    else
      {:error, :invalid_import_review_selection}
    end
  end

  defp accumulate_selected_decision(%{"speaker" => speaker, "action" => action} = selected, {:ok, decisions})
       when is_binary(speaker) and action in @actions do
    decision =
      case {action, Map.get(selected, "target_speaker")} do
        {"map_to_sheet", target} when is_binary(target) and target != "" ->
          %{action: action, target_speaker: target}

        {direct, nil} when direct in @direct_actions ->
          %{action: direct, target_speaker: nil}

        _invalid ->
          :invalid
      end

    cond do
      decision == :invalid ->
        {:halt, {:error, :invalid_import_review_selection}}

      Map.has_key?(decisions, speaker) ->
        {:halt, {:error, :invalid_import_review_selection}}

      true ->
        {:cont, {:ok, Map.put(decisions, speaker, decision)}}
    end
  end

  defp accumulate_selected_decision(_invalid, _accumulator) do
    {:halt, {:error, :invalid_import_review_selection}}
  end

  defp validate_complete_alias_mappings(decisions, alias_pairs) do
    Enum.reduce_while(decisions, :ok, fn {speaker, decision}, :ok ->
      case validate_alias_mapping(speaker, decision, decisions, alias_pairs, MapSet.new(Map.keys(decisions))) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_partial_alias_mappings(decisions, alias_pairs, expected) do
    Enum.reduce_while(decisions, :ok, fn {speaker, decision}, :ok ->
      case validate_partial_alias_mapping(speaker, decision, decisions, alias_pairs, expected) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_alias_mapping(
         speaker,
         %{action: "map_to_sheet", target_speaker: target},
         decisions,
         alias_pairs,
         expected
       ) do
    with true <- target != speaker,
         true <- MapSet.member?(expected, target),
         true <- alias_pair?(alias_pairs, speaker, target),
         %{action: "create_sheet"} <- Map.get(decisions, target) do
      :ok
    else
      _invalid -> {:error, :invalid_import_review_selection}
    end
  end

  defp validate_alias_mapping(_speaker, %{action: action, target_speaker: nil}, _decisions, _alias_pairs, _expected)
       when action in @direct_actions, do: :ok

  defp validate_alias_mapping(_speaker, _decision, _decisions, _alias_pairs, _expected),
    do: {:error, :invalid_import_review_selection}

  defp validate_partial_alias_mapping(
         speaker,
         %{action: "map_to_sheet", target_speaker: target},
         decisions,
         alias_pairs,
         expected
       ) do
    with true <- target != speaker,
         true <- MapSet.member?(expected, target),
         true <- alias_pair?(alias_pairs, speaker, target),
         target_decision when is_nil(target_decision) or is_map(target_decision) <-
           Map.get(decisions, target),
         true <- is_nil(target_decision) or target_decision.action == "create_sheet" do
      :ok
    else
      _invalid -> {:error, :invalid_import_review_selection}
    end
  end

  defp validate_partial_alias_mapping(
         _speaker,
         %{action: action, target_speaker: nil},
         _decisions,
         _alias_pairs,
         _expected
       )
       when action in @direct_actions, do: :ok

  defp validate_partial_alias_mapping(_speaker, _decision, _decisions, _alias_pairs, _expected),
    do: {:error, :invalid_import_review_selection}

  defp alias_pair?(alias_pairs, left, right) do
    MapSet.member?(alias_pairs, [left, right] |> Enum.sort() |> List.to_tuple())
  end

  defp validate_plan_occurrences(data, review_entries) do
    expected = Map.new(review_entries, &{&1.speaker, &1.occurrences})
    actual = speaker_occurrences(data)

    if actual == expected, do: :ok, else: {:error, :invalid_import_review}
  end

  defp speaker_occurrences(data) do
    data
    |> Map.get("flows", [])
    |> Enum.flat_map(&Map.get(&1, "nodes", []))
    |> Enum.reduce(%{}, fn node, counts ->
      case get_in(node, ["data", "import_yarn_speaker"]) do
        speaker when is_binary(speaker) -> Map.update(counts, speaker, 1, &(&1 + 1))
        _not_a_speaker_line -> counts
      end
    end)
  end

  defp apply_to_data(data, review_data, review_entries, selected_actions) do
    selected_speakers =
      review_entries
      |> Enum.filter(&(get_in(selected_actions, [&1.speaker, :action]) == "create_sheet"))
      |> Enum.map(& &1.speaker)

    {sheets, speaker_sheet_ids} = rebuild_speaker_sheets(data["sheets"], selected_speakers)

    with {:ok, flows} <- apply_to_flows(data["flows"], selected_actions, speaker_sheet_ids) do
      serialized_decisions = serialize_decisions(selected_actions)

      {:ok,
       data
       |> Map.put("sheets", sheets)
       |> Map.put("flows", flows)
       |> Map.put("import_review", review_data)
       |> Map.delete("import_review_draft")
       |> Map.put("import_review_resolution", %{
         "version" => 2,
         "decisions" => serialized_decisions,
         "decision_fingerprint" => decision_fingerprint(selected_actions)
       })}
    end
  end

  defp serialize_decisions(decisions) do
    decisions
    |> Enum.sort_by(fn {speaker, _decision} -> speaker end)
    |> Enum.map(fn {speaker, decision} ->
      maybe_put_target_speaker(%{"speaker" => speaker, "action" => decision.action}, decision.target_speaker)
    end)
  end

  defp maybe_put_target_speaker(serialized, nil), do: serialized

  defp maybe_put_target_speaker(serialized, target), do: Map.put(serialized, "target_speaker", target)

  defp decision_fingerprint(decisions) do
    decisions
    |> Enum.map(fn {speaker, decision} ->
      {speaker, decision.action, decision.target_speaker}
    end)
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp rebuild_speaker_sheets(sheets, selected_speakers) when is_list(sheets) do
    retained_sheets =
      Enum.reject(sheets, fn
        %{"id" => "speaker_sheet_" <> _digest} -> true
        _other -> false
      end)

    SpeakerSheets.append(retained_sheets, selected_speakers)
  end

  defp rebuild_speaker_sheets(_sheets, _selected_speakers), do: {[], %{}}

  defp apply_to_flows(flows, selected_actions, speaker_sheet_ids) when is_list(flows) do
    flows
    |> Enum.reduce_while({:ok, []}, fn flow, {:ok, resolved_flows} ->
      case apply_to_flow(flow, selected_actions, speaker_sheet_ids) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | resolved_flows]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved_flows} -> {:ok, Enum.reverse(resolved_flows)}
      error -> error
    end
  end

  defp apply_to_flows(_flows, _selected_actions, _speaker_sheet_ids), do: {:error, :invalid_import_review}

  defp apply_to_flow(%{"nodes" => nodes} = flow, selected_actions, speaker_sheet_ids) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, resolved_nodes} ->
      case apply_to_node(node, selected_actions, speaker_sheet_ids) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | resolved_nodes]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved_nodes} -> {:ok, Map.put(flow, "nodes", Enum.reverse(resolved_nodes))}
      error -> error
    end
  end

  defp apply_to_flow(_flow, _selected_actions, _speaker_sheet_ids), do: {:error, :invalid_import_review}

  defp apply_to_node(%{"type" => "dialogue", "data" => data} = node, selected_actions, speaker_sheet_ids)
       when is_map(data) do
    case {Map.get(data, "import_yarn_speaker"), Map.get(data, "import_yarn_inherited_speaker")} do
      {speaker, _inherited} when is_binary(speaker) ->
        resolve_speaker_node(node, data, speaker, selected_actions, speaker_sheet_ids)

      {_explicit, speaker} when is_binary(speaker) ->
        resolve_inherited_speaker_node(node, data, speaker, selected_actions, speaker_sheet_ids)

      _ordinary_dialogue ->
        {:ok, node}
    end
  end

  defp apply_to_node(%{"data" => data} = node, _selected_actions, _speaker_sheet_ids) when is_map(data) do
    if Map.has_key?(data, "import_yarn_speaker"),
      do: {:error, :invalid_import_review},
      else: {:ok, node}
  end

  defp apply_to_node(_node, _selected_actions, _speaker_sheet_ids), do: {:error, :invalid_import_review}

  defp resolve_speaker_node(node, data, speaker, selected_actions, speaker_sheet_ids) do
    # The normalized-plan contract permits dialogue without `responses` when
    # there are no choices. Speaker resolution never traverses that collection,
    # and the materializer already treats an absent value as an empty list.
    with {:ok, decision} <- Map.fetch(selected_actions, speaker),
         {:ok, source} <- explicit_speaker_source(data, speaker) do
      {:ok, Map.put(node, "data", resolve_explicit_speaker_data(data, speaker, decision, speaker_sheet_ids, source))}
    else
      _missing_or_invalid -> {:error, :invalid_import_review}
    end
  end

  defp resolve_explicit_speaker_data(data, speaker, decision, speaker_sheet_ids, source) do
    {speaker_sheet_id, rendered_text} =
      case decision.action do
        "create_sheet" ->
          {Map.fetch!(speaker_sheet_ids, speaker), render_speaker_source(source, :body, data)}

        "preserve_literal" ->
          {nil, render_speaker_source(source, :full, data)}

        "map_to_sheet" ->
          {Map.fetch!(speaker_sheet_ids, decision.target_speaker), render_speaker_source(source, :body, data)}
      end

    data
    |> Map.drop(@speaker_metadata_keys)
    |> Map.put("speaker_sheet_id", speaker_sheet_id)
    |> Map.put("text", rendered_text)
    |> retain_review_identity(data)
    |> retain_speaker_source(source)
  end

  # Current plans keep exactly one raw source for an explicit speaker: the
  # complete authored line. The literal-source candidate reads revisions made
  # before that consolidation; once applied, those plans are rewritten to the
  # same single-source shape. Plans old enough to have only rendered literal
  # text retain that one legacy value so their decisions can still be revised.
  defp explicit_speaker_source(data, speaker) do
    literal_source = Map.get(data, "import_yarn_literal_source_text")
    source_text = Map.get(data, "import_yarn_source_text")

    cond do
      match?({:ok, {:raw, _full, _body}}, split_explicit_source(literal_source, speaker)) ->
        split_explicit_source(literal_source, speaker)

      is_binary(Map.get(data, "import_yarn_literal_text")) and is_binary(source_text) ->
        # Transitional plans stored the semantic body in `source_text` and the
        # rendered full line separately. Rebuild a canonical raw full line;
        # current plans never enter this branch because they have no literal key.
        {:ok, {:raw, "#{speaker}: #{source_text}", source_text}}

      match?({:ok, {:raw, _full, _body}}, split_explicit_source(source_text, speaker)) ->
        split_explicit_source(source_text, speaker)

      true ->
        case Map.get(data, "import_yarn_literal_text") do
          literal_text when is_binary(literal_text) -> legacy_rendered_source(literal_text, speaker)
          _missing_legacy_text -> {:error, :invalid_import_review}
        end
    end
  end

  defp split_explicit_source(source_text, speaker) when is_binary(source_text) do
    case SpeakerClassifier.split(source_text) do
      {^speaker, body} -> {:ok, {:raw, source_text, body}}
      _other -> {:error, :invalid_import_review}
    end
  end

  defp split_explicit_source(_source_text, _speaker), do: {:error, :invalid_import_review}

  defp legacy_rendered_source(literal_text, speaker) do
    rendered_prefix = Expression.interpolate(speaker, :dialogue) <> ":"

    case literal_text do
      ^rendered_prefix <> remainder ->
        case String.trim_leading(remainder) do
          "" -> {:error, :invalid_import_review}
          body_text -> {:ok, {:legacy_rendered_only, literal_text, body_text}}
        end

      _wrong_speaker_prefix ->
        {:error, :invalid_import_review}
    end
  end

  defp render_speaker_source({:raw, full_source, _body_source}, :full, _data),
    do: Expression.interpolate(full_source, :dialogue)

  defp render_speaker_source({:raw, _full_source, body_source}, :body, _data),
    do: Expression.interpolate(body_source, :dialogue)

  defp render_speaker_source({:legacy_rendered_only, literal_text, _body_text}, :full, _data), do: literal_text

  defp render_speaker_source({:legacy_rendered_only, _literal_text, body_text}, :body, _data), do: body_text

  defp retain_speaker_source(data, {:raw, full_source, _body_source}) do
    Map.put(data, "import_yarn_source_text", full_source)
  end

  defp retain_speaker_source(data, {:legacy_rendered_only, literal_text, _body_text}) do
    Map.put(data, "import_yarn_literal_text", literal_text)
  end

  defp resolve_inherited_speaker_node(node, data, speaker, selected_actions, speaker_sheet_ids) do
    case Map.fetch(selected_actions, speaker) do
      {:ok, decision} ->
        clean_data = Map.drop(data, @speaker_metadata_keys)

        speaker_sheet_id =
          case decision.action do
            "create_sheet" -> Map.fetch!(speaker_sheet_ids, speaker)
            "preserve_literal" -> nil
            "map_to_sheet" -> Map.fetch!(speaker_sheet_ids, decision.target_speaker)
          end

        {:ok,
         Map.put(
           node,
           "data",
           clean_data
           |> Map.put("speaker_sheet_id", speaker_sheet_id)
           |> retain_review_identity(data)
           |> retain_source_text(data)
         )}

      _missing_or_invalid ->
        {:error, :invalid_import_review}
    end
  end

  defp retain_review_identity(data, source_data) do
    Map.merge(data, Map.take(source_data, ~w(import_yarn_inherited_speaker import_yarn_speaker)))
  end

  defp retain_source_text(data, %{"import_yarn_source_text" => source_text}) when is_binary(source_text) do
    Map.put(data, "import_yarn_source_text", source_text)
  end

  defp retain_source_text(data, _source_data), do: data
end
