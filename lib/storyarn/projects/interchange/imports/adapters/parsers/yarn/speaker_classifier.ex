defmodule Storyarn.Projects.Imports.Parsers.Yarn.SpeakerClassifier do
  @moduledoc false

  alias Storyarn.Projects.Imports.ImportIssue

  @max_review_items 1_000
  @max_alias_work 200_000
  @minimum_alias_length 5
  @minimum_alias_frequency_ratio 3

  @type speaker_stats :: %{
          count: pos_integer(),
          common_scopes: MapSet.t(String.t()),
          first_meta: map(),
          followed_by_options: boolean(),
          scope_regions: %{optional(String.t()) => MapSet.t(term())}
        }

  @type result :: %{
          sheet_speakers: [String.t()],
          presentation_channels: MapSet.t(String.t()),
          issues: [ImportIssue.t()],
          review: map(),
          possible_alias_count: non_neg_integer()
        }

  @spec classify([map()]) :: result()
  def classify(documents) when is_list(documents) do
    {speaker_stats, scope_counts} = collect_occurrences(documents)
    clear_scopes = collect_clear_scopes(documents)

    channel_scopes =
      classify_presentation_channels(speaker_stats, scope_counts, clear_scopes)

    presentation_channels = channel_scopes |> Map.keys() |> MapSet.new()

    dynamic_speakers =
      speaker_stats
      |> Map.keys()
      |> Enum.filter(&dynamic_speaker?/1)
      |> MapSet.new()

    preserved_speakers = MapSet.union(presentation_channels, dynamic_speakers)

    sheet_speakers =
      speaker_stats
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(preserved_speakers, &1))
      |> Enum.sort()

    {aliases, possible_alias_count, alias_analysis_truncated?} =
      possible_aliases(sheet_speakers, speaker_stats)

    channel_issues =
      Enum.map(channel_scopes, fn {speaker, _scope} ->
        first_meta = speaker_stats |> Map.fetch!(speaker) |> Map.fetch!(:first_meta)
        new_issue(:yarn_presentation_channel_preserved, first_meta)
      end)

    alias_issues =
      Enum.map(aliases, fn alias_review ->
        speaker = alias_review["less_frequent"]
        first_meta = speaker_stats |> Map.fetch!(speaker) |> Map.fetch!(:first_meta)
        new_issue(:possible_yarn_speaker_alias, first_meta)
      end)

    %{
      sheet_speakers: sheet_speakers,
      presentation_channels: presentation_channels,
      issues: channel_issues ++ alias_issues,
      review:
        build_review(
          speaker_stats,
          channel_scopes,
          scope_counts,
          aliases,
          possible_alias_count,
          alias_analysis_truncated?
        ),
      possible_alias_count: possible_alias_count
    }
  end

  # A character name may contain spaces — "Captain Reyes", "Old Man" — matching
  # every shipped Yarn implementation, which reads the name as the text up to
  # the first colon. The class stays narrower than Yarn's on purpose: letters,
  # digits, space and `_.'-` up to 60 chars, so a long prose clause ending in a
  # colon is dialogue, not a character. A `\:` escape (Yarn 3.2+) suppresses
  # the split entirely; the escape is unescaped in the returned text.
  @speaker_pattern ~r/^([\p{L}\p{N}_][\p{L}\p{N} _.'-]{0,59}):\s+(.+)$/u

  # A speaker that is exactly one `{$variable}` interpolation is recognized
  # separately so `dynamic_speaker?/1` can route it to the preserve-literal
  # review instead of losing the line's computed speaker in its text.
  @dynamic_speaker_pattern ~r/^(\{\$[A-Za-z_][A-Za-z0-9_.]*\}):\s+(.+)$/u

  @spec split(String.t()) :: {String.t() | nil, String.t()}
  def split(text) when is_binary(text) do
    case run_speaker_patterns(text) do
      [speaker, dialogue] ->
        if String.downcase(speaker) in ["http", "https"],
          do: {nil, unescape_colons(text)},
          else: {String.trim(speaker), unescape_colons(dialogue)}

      _no_speaker ->
        {nil, unescape_colons(text)}
    end
  end

  defp run_speaker_patterns(text) do
    Regex.run(@speaker_pattern, text, capture: :all_but_first) ||
      Regex.run(@dynamic_speaker_pattern, text, capture: :all_but_first)
  end

  @doc false
  @spec unescape_colons(String.t()) :: String.t()
  def unescape_colons(text), do: String.replace(text, "\\:", ":")

  defp collect_occurrences(documents) do
    Enum.reduce(documents, {%{}, %{}}, fn document, {occurrences, scope_counts} ->
      collect_sequence_occurrences(
        document.body,
        %{},
        occurrences,
        scope_counts
      )
    end)
  end

  defp collect_sequence_occurrences(items, inherited_scopes, occurrences, scope_counts) do
    spans = matched_scope_spans(items)
    events = scope_events(spans)

    scope_counts =
      Enum.reduce(spans, scope_counts, fn
        {scope, _region_id, _start_index, _end_index}, counts ->
          Map.update(counts, scope, 1, &(&1 + 1))
      end)

    following_items =
      case items do
        [] -> []
        [_first | rest] -> rest ++ [nil]
      end

    {occurrences, scope_counts, _active_scope_counts} =
      items
      |> Enum.zip(following_items)
      |> Enum.with_index()
      |> Enum.reduce(
        {occurrences, scope_counts, %{}},
        fn {{item, next_item}, index}, {occurrences, scope_counts, active_scope_counts} ->
          active_scope_counts = apply_scope_events(active_scope_counts, Map.get(events, index, []))

          scope_regions =
            Map.merge(active_scope_counts, inherited_scopes, fn _scope, active, inherited ->
              MapSet.union(active, inherited)
            end)

          {occurrences, scope_counts} =
            collect_item_occurrences(
              item,
              scope_regions,
              match?({:options, _options, _meta}, next_item),
              occurrences,
              scope_counts
            )

          {occurrences, scope_counts, active_scope_counts}
        end
      )

    {occurrences, scope_counts}
  end

  defp collect_item_occurrences({:line, text, meta}, scope_regions, followed_by_options, occurrences, scope_counts) do
    case split(text) do
      {speaker, _dialogue} when is_binary(speaker) ->
        initial_stats = %{
          count: 1,
          common_scopes: scope_regions |> Map.keys() |> MapSet.new(),
          first_meta: meta,
          followed_by_options: followed_by_options,
          scope_regions: scope_regions
        }

        speaker_stats =
          Map.update(occurrences, speaker, initial_stats, fn stats ->
            %{
              stats
              | count: stats.count + 1,
                common_scopes:
                  MapSet.intersection(
                    stats.common_scopes,
                    scope_regions |> Map.keys() |> MapSet.new()
                  ),
                followed_by_options: stats.followed_by_options or followed_by_options,
                scope_regions:
                  Map.merge(stats.scope_regions, scope_regions, fn _scope, existing, current ->
                    MapSet.union(existing, current)
                  end)
            }
          end)

        {speaker_stats, scope_counts}

      _other ->
        {occurrences, scope_counts}
    end
  end

  defp collect_item_occurrences({:options, options, _meta}, scopes, _followed_by_options, occurrences, scope_counts) do
    Enum.reduce(options, {occurrences, scope_counts}, fn option, {occurrences, scope_counts} ->
      collect_sequence_occurrences(option.body, scopes, occurrences, scope_counts)
    end)
  end

  defp collect_item_occurrences(
         {:if, branches, else_body, _meta},
         scopes,
         _followed_by_options,
         occurrences,
         scope_counts
       ) do
    {occurrences, scope_counts} =
      Enum.reduce(branches, {occurrences, scope_counts}, fn branch, {occurrences, scope_counts} ->
        collect_sequence_occurrences(branch.body, scopes, occurrences, scope_counts)
      end)

    collect_sequence_occurrences(else_body, scopes, occurrences, scope_counts)
  end

  defp collect_item_occurrences(_item, _scopes, _followed_by_options, occurrences, scope_counts),
    do: {occurrences, scope_counts}

  defp matched_scope_spans(items) do
    {_stack, spans} =
      items
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {item, index}, {stack, spans} ->
        case command_boundary(item) do
          {:start, scope, meta} ->
            region_id = {Map.get(meta, :source), Map.get(meta, :line), index}
            {[{scope, region_id, index} | stack], spans}

          {:end, scope} ->
            close_scope(stack, spans, scope, index)

          nil ->
            {stack, spans}
        end
      end)

    spans
  end

  defp command_boundary({:command, "start_" <> scope, args, meta}) when scope != "" do
    if String.trim(args) == "", do: {:start, scope, meta}
  end

  defp command_boundary({:command, "end_" <> scope, args, _meta}) when scope != "" do
    if String.trim(args) == "", do: {:end, scope}
  end

  defp command_boundary(_item), do: nil

  defp close_scope([{scope, region_id, start_index} | stack], spans, scope, end_index),
    do: {stack, [{scope, region_id, start_index, end_index} | spans]}

  # Only properly nested, same-sequence pairs provide evidence. A mismatched
  # closer leaves the stack untouched so malformed command streams can never
  # cause content to be reclassified.
  defp close_scope(stack, spans, _scope, _end_index), do: {stack, spans}

  defp scope_events(spans) do
    Enum.reduce(spans, %{}, fn {scope, region_id, start_index, end_index}, events ->
      events
      |> Map.update(
        start_index + 1,
        [{:enter, scope, region_id}],
        &[{:enter, scope, region_id} | &1]
      )
      |> Map.update(end_index, [{:leave, scope, region_id}], &[{:leave, scope, region_id} | &1])
    end)
  end

  defp apply_scope_events(active_scope_counts, events) do
    events
    |> Enum.sort_by(fn
      {:enter, _scope, _region_id} -> 0
      {:leave, _scope, _region_id} -> 1
    end)
    |> Enum.reduce(active_scope_counts, fn
      {:enter, scope, region_id}, regions ->
        Map.update(
          regions,
          scope,
          MapSet.new([region_id]),
          &MapSet.put(&1, region_id)
        )

      {:leave, scope, region_id}, regions ->
        remaining =
          regions
          |> Map.get(scope, MapSet.new())
          |> MapSet.delete(region_id)

        if MapSet.size(remaining) == 0 do
          Map.delete(regions, scope)
        else
          Map.put(regions, scope, remaining)
        end
    end)
  end

  defp collect_clear_scopes(documents) do
    Enum.reduce(documents, MapSet.new(), fn document, clear_scopes ->
      collect_clear_scopes_from_items(document.body, clear_scopes)
    end)
  end

  defp collect_clear_scopes_from_items(items, clear_scopes) do
    Enum.reduce(items, clear_scopes, fn
      {:command, "clear_" <> scope, args, _meta}, acc when scope != "" ->
        if String.trim(args) == "", do: MapSet.put(acc, scope), else: acc

      {:options, options, _meta}, acc ->
        Enum.reduce(options, acc, fn option, nested_acc ->
          collect_clear_scopes_from_items(option.body, nested_acc)
        end)

      {:if, branches, else_body, _meta}, acc ->
        acc =
          Enum.reduce(branches, acc, fn branch, nested_acc ->
            collect_clear_scopes_from_items(branch.body, nested_acc)
          end)

        collect_clear_scopes_from_items(else_body, acc)

      _item, acc ->
        acc
    end)
  end

  defp classify_presentation_channels(speaker_stats, scope_counts, clear_scopes) do
    provisional =
      Map.new(speaker_stats, fn {speaker, stats} ->
        {speaker, matching_common_scope(speaker, stats)}
      end)

    qualifying_scopes =
      provisional
      |> Enum.reject(fn {_speaker, scope} -> is_nil(scope) end)
      |> Enum.group_by(fn {_speaker, scope} -> scope end)
      |> Enum.filter(fn {scope, candidates} ->
        length(candidates) >= 2 and
          Map.get(scope_counts, scope, 0) >= 2 and
          MapSet.member?(clear_scopes, scope)
      end)
      |> MapSet.new(fn {scope, _candidates} -> scope end)

    provisional
    |> Enum.filter(fn {_speaker, scope} -> MapSet.member?(qualifying_scopes, scope) end)
    |> Map.new()
  end

  defp matching_common_scope(_speaker, %{followed_by_options: true}), do: nil

  defp matching_common_scope(speaker, %{common_scopes: common_scopes, scope_regions: scope_regions}) do
    common_scopes
    |> Enum.filter(fn scope ->
      speaker_matches_scope?(speaker, scope) and
        scope_regions |> Map.get(scope, MapSet.new()) |> MapSet.size() >= 2
    end)
    |> Enum.sort()
    |> List.first()
  end

  defp speaker_matches_scope?(speaker, scope) do
    speaker_tokens = semantic_tokens(speaker)
    scope_tokens = semantic_tokens(scope)

    length(speaker_tokens) >= 2 and
      scope_tokens != [] and
      List.first(speaker_tokens) == List.last(scope_tokens)
  end

  defp semantic_tokens(value) do
    value
    |> String.replace(~r/([\p{Lu}]+)([\p{Lu}][\p{Ll}])/u, "\\1 \\2")
    |> String.replace(~r/([\p{Ll}\p{N}])([\p{Lu}])/u, "\\1 \\2")
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.map(&String.downcase/1)
  end

  defp possible_aliases(speakers, speaker_stats) do
    normalized_index =
      speakers
      |> Enum.group_by(&normalize_alias/1)
      |> Map.new(fn {normalized, variants} ->
        {normalized, alias_group(normalized, variants, speaker_stats)}
      end)

    {reviews, count, _work, truncated?} =
      normalized_index
      |> collect_normalized_variant_aliases()
      |> collect_transposition_aliases(normalized_index)

    {Enum.reverse(reviews), count, truncated?}
  end

  defp alias_group(normalized, variants, speaker_stats) do
    variant_counts =
      variants
      |> Enum.map(fn speaker ->
        %{
          speaker: speaker,
          count: speaker_stats |> Map.fetch!(speaker) |> Map.fetch!(:count)
        }
      end)
      |> Enum.sort_by(& &1.speaker)

    representative = Enum.min_by(variant_counts, &{-&1.count, &1.speaker})

    %{
      normalized: normalized,
      representative: representative.speaker,
      count: Enum.sum(Enum.map(variant_counts, & &1.count)),
      variants: variant_counts
    }
  end

  defp collect_normalized_variant_aliases(normalized_index) do
    normalized_index
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce_while({[], 0, 0, false}, fn normalized, acc ->
      group = Map.fetch!(normalized_index, normalized)

      case collect_group_variant_aliases(group, acc) do
        {_reviews, _count, _work, true} = halted -> {:halt, halted}
        continued -> {:cont, continued}
      end
    end)
  end

  defp collect_group_variant_aliases(group, acc) do
    group.variants
    |> Enum.reject(&(&1.speaker == group.representative))
    |> Enum.reduce_while(acc, fn variant, {reviews, count, work, _truncated?} ->
      if work >= @max_alias_work do
        {:halt, {reviews, count, work, true}}
      else
        review = normalized_variant_alias_review(group, variant)
        {:cont, add_alias_review(review, {reviews, count, work + 1, false})}
      end
    end)
  end

  defp collect_transposition_aliases({_reviews, _count, _work, true} = halted, _normalized_index), do: halted

  defp collect_transposition_aliases(initial, normalized_index) do
    normalized_index
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce_while(initial, fn normalized, acc ->
      case collect_alias_candidates(normalized, acc, normalized_index) do
        {_reviews, _count, _work, true} = halted -> {:halt, halted}
        continued -> {:cont, continued}
      end
    end)
  end

  defp collect_alias_candidates(normalized, acc, normalized_index) do
    normalized
    |> adjacent_transpositions()
    |> Enum.uniq()
    |> Enum.reduce_while(acc, fn candidate_normalized, {reviews, count, work, _truncated?} ->
      if work >= @max_alias_work do
        {:halt, {reviews, count, work, true}}
      else
        next_acc =
          consider_alias_candidate(
            normalized,
            candidate_normalized,
            {reviews, count, work + 1, false},
            normalized_index
          )

        {:cont, next_acc}
      end
    end)
  end

  defp consider_alias_candidate(normalized, candidate_normalized, acc, normalized_index)
       when normalized < candidate_normalized do
    with %{count: _count} = left <- Map.get(normalized_index, normalized),
         %{count: _count} = right <- Map.get(normalized_index, candidate_normalized),
         true <- probable_alias_pair?(left, right) do
      add_probable_alias(left, right, acc)
    else
      _not_a_candidate -> acc
    end
  end

  defp consider_alias_candidate(_normalized, _candidate_normalized, acc, _normalized_index), do: acc

  defp add_probable_alias(left, right, {reviews, count, work, truncated?}) when count < @max_review_items do
    add_alias_review(alias_review(left, right), {reviews, count, work, truncated?})
  end

  defp add_probable_alias(_left, _right, {reviews, count, work, truncated?}) do
    {reviews, count + 1, work, truncated?}
  end

  defp add_alias_review(review, {reviews, count, work, truncated?}) when count < @max_review_items do
    {[review | reviews], count + 1, work, truncated?}
  end

  defp add_alias_review(_review, {reviews, count, work, truncated?}) do
    {reviews, count + 1, work, truncated?}
  end

  defp normalize_alias(speaker) do
    speaker
    |> :unicode.characters_to_nfkc_binary()
    |> :string.casefold()
    |> :unicode.characters_to_binary()
  end

  defp adjacent_transpositions(normalized) do
    graphemes = String.graphemes(normalized)

    if length(graphemes) < @minimum_alias_length do
      []
    else
      graphemes
      |> Enum.with_index()
      |> Enum.drop(-1)
      |> Enum.reject(fn {grapheme, index} -> grapheme == Enum.at(graphemes, index + 1) end)
      |> Enum.map(fn {_grapheme, index} ->
        left = Enum.at(graphemes, index)
        right = Enum.at(graphemes, index + 1)

        graphemes
        |> List.replace_at(index, right)
        |> List.replace_at(index + 1, left)
        |> Enum.join()
      end)
    end
  end

  defp probable_alias_pair?(left, right) do
    left_graphemes = String.graphemes(left.normalized)
    right_graphemes = String.graphemes(right.normalized)
    low_count = min(left.count, right.count)
    high_count = max(left.count, right.count)

    length(left_graphemes) >= @minimum_alias_length and
      length(left_graphemes) == length(right_graphemes) and
      List.first(left_graphemes) == List.first(right_graphemes) and
      List.last(left_graphemes) == List.last(right_graphemes) and
      high_count >= low_count * @minimum_alias_frequency_ratio
  end

  defp alias_review(left, right) do
    {more_frequent, less_frequent} =
      more_and_less_frequent(
        left.representative,
        left.count,
        right.representative,
        right.count
      )

    %{
      "left" => left.representative,
      "left_occurrences" => left.count,
      "right" => right.representative,
      "right_occurrences" => right.count,
      "more_frequent" => more_frequent,
      "less_frequent" => less_frequent,
      "evidence" => "single_adjacent_transposition_with_dominant_frequency",
      "decision" => "review"
    }
  end

  defp normalized_variant_alias_review(group, variant) do
    representative = Enum.find(group.variants, &(&1.speaker == group.representative))

    %{
      "left" => representative.speaker,
      "left_occurrences" => representative.count,
      "right" => variant.speaker,
      "right_occurrences" => variant.count,
      "more_frequent" => representative.speaker,
      "less_frequent" => variant.speaker,
      "evidence" => "same_nfkc_casefold",
      "decision" => "review"
    }
  end

  defp more_and_less_frequent(left, left_count, right, right_count) when left_count > right_count, do: {left, right}

  defp more_and_less_frequent(left, _left_count, right, _right_count), do: {right, left}

  defp build_review(speaker_stats, channel_scopes, scope_counts, aliases, possible_alias_count, alias_analysis_truncated?) do
    preserved_speaker_set =
      speaker_stats
      |> Map.keys()
      |> Enum.filter(&(Map.has_key?(channel_scopes, &1) or dynamic_speaker?(&1)))
      |> MapSet.new()

    preserved_speakers = preserved_speaker_set |> Enum.to_list() |> Enum.sort()

    sheet_speakers =
      speaker_stats
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(preserved_speaker_set, &1))
      |> Enum.sort()

    decisions =
      (preserved_speakers ++ sheet_speakers)
      |> Enum.take(@max_review_items)
      |> Enum.map(fn speaker ->
        stats = Map.fetch!(speaker_stats, speaker)

        case {dynamic_speaker?(speaker), Map.fetch(channel_scopes, speaker)} do
          {true, _scope_result} ->
            %{
              "speaker" => speaker,
              "suggested_action" => "preserve_literal",
              "confidence" => "high",
              "reasons" => ["dynamic_speaker_expression"],
              "occurrences" => stats.count
            }

          {false, {:ok, scope}} ->
            %{
              "speaker" => speaker,
              "suggested_action" => "preserve_literal",
              "confidence" => "high",
              "reasons" => ["repeated_scoped_presentation_channel"],
              "scope" => scope,
              "matched_scope_regions" => Map.fetch!(scope_counts, scope),
              "speaker_matched_scope_regions" => stats.scope_regions |> Map.fetch!(scope) |> MapSet.size(),
              "occurrences" => stats.count
            }

          {false, :error} ->
            %{
              "speaker" => speaker,
              "suggested_action" => "create_sheet",
              "confidence" => "medium",
              "reasons" => ["literal_character_name"],
              "occurrences" => stats.count
            }
        end
      end)

    speaker_decision_count = map_size(speaker_stats)
    preserved_channel_count = length(preserved_speakers)
    sheet_speaker_count = speaker_decision_count - preserved_channel_count

    %{
      "speaker_decisions" => decisions,
      "speaker_decision_count" => speaker_decision_count,
      "speaker_decisions_truncated" => speaker_decision_count > @max_review_items,
      "sheet_speaker_count" => sheet_speaker_count,
      "preserved_channel_count" => preserved_channel_count,
      "possible_speaker_aliases" => aliases,
      "possible_speaker_alias_count" => possible_alias_count,
      "possible_speaker_aliases_truncated" => alias_analysis_truncated? or possible_alias_count > @max_review_items,
      "requires_acknowledgement" => speaker_decision_count > 0 or possible_alias_count > 0
    }
  end

  defp dynamic_speaker?(speaker) do
    Regex.match?(~r/^\{\$[A-Za-z_][A-Za-z0-9_.]*\}$/, speaker)
  end

  defp new_issue(code, meta) do
    ImportIssue.new(:warning, code,
      source: Map.get(meta, :source),
      line: Map.get(meta, :line)
    )
  end
end
