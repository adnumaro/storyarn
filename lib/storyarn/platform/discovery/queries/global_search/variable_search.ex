defmodule Storyarn.Platform.GlobalSearch.VariableSearch do
  @moduledoc """
  Deterministic variable-definition and occurrence search for the `$` palette
  prefix.

  Definitions are resolved inside one already-authorized project. An
  unambiguous exact reference includes its active read/write occurrences.
  Plain ambiguous names return qualified completions, while predicates first
  filter every exact definition by its authored initial value. Qualified
  suggestions only appear when that predicate has no matches.
  """

  alias Storyarn.Platform.GlobalSearch.VariableQuery
  alias Storyarn.Projects
  alias Storyarn.Sheets

  @default_limit 25
  @max_limit 50
  @usage_scan_limit 250
  @predicate_types ~w(text rich_text number select boolean date)

  @spec search(integer(), String.t(), keyword()) :: %{
          optional(:fallback) => :qualified_references,
          mode: :variables,
          items: [map()],
          truncated: boolean()
        }
  def search(project_id, query, opts \\ []) do
    limit = bounded_limit(opts)

    case VariableQuery.parse(query) do
      {:ok, parsed} ->
        definitions_page =
          Sheets.search_variable_definitions(
            project_id,
            {:contains, parsed.reference},
            limit: @max_limit
          )

        exact_definitions_page = load_exact_definitions(project_id, parsed)

        build_page(project_id, parsed, definitions_page, exact_definitions_page, limit)

      _invalid ->
        %{mode: :variables, items: [], truncated: false}
    end
  end

  defp build_page(project_id, %VariableQuery{operator: nil} = query, definitions_page, exact_definitions_page, limit) do
    case exact_definitions_page.items do
      [definition] ->
        usage_page = Projects.list_project_variable_usages(project_id, definition, limit: limit)

        items =
          ([definition_hit(definition, :owner)] ++ Enum.map(usage_page.items, &usage_hit/1))
          |> Enum.uniq_by(& &1.id)
          |> Enum.sort_by(&sort_key/1)

        variable_page(
          items,
          limit,
          exact_definitions_page.truncated or usage_page.truncated
        )

      _none_or_ambiguous ->
        items =
          definitions_page.items
          |> Enum.map(&definition_completion_hit(&1, query))
          |> Enum.sort_by(&sort_key/1)

        variable_page(
          items,
          limit,
          definitions_page.truncated or exact_definitions_page.truncated
        )
    end
  end

  defp build_page(project_id, %VariableQuery{} = query, definitions_page, exact_definitions_page, limit) do
    {matches, matches_truncated} =
      predicate_matches(
        project_id,
        exact_definitions_page,
        query,
        limit
      )

    if matches == [] do
      suggestions_page =
        if exact_definitions_page.items == [],
          do: definitions_page,
          else: exact_definitions_page

      predicate_fallback_page(suggestions_page, query, limit)
    else
      variable_page(
        matches,
        limit,
        matches_truncated
      )
    end
  end

  defp predicate_matches(_project_id, %{items: []}, _query, _limit), do: {[], false}

  defp predicate_matches(project_id, %{items: [definition], truncated: false}, query, _limit) do
    usage_page =
      Projects.list_project_variable_usages(
        project_id,
        definition,
        limit: @usage_scan_limit
      )

    initial_matches =
      project_id
      |> initial_value_matches_page(query, 1)
      |> Map.fetch!(:items)
      |> Enum.map(&definition_hit(&1, :initial))

    string_aliases =
      Sheets.variable_predicate_string_aliases(
        project_id,
        definition,
        query.operator,
        query.literal
      )

    occurrence_matches =
      usage_page.items
      |> Enum.filter(&occurrence_matches?(&1, definition, query, string_aliases))
      |> Enum.map(&usage_hit/1)

    matches =
      (initial_matches ++ occurrence_matches)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&sort_key/1)

    {matches, usage_page.truncated}
  end

  defp predicate_matches(project_id, _exact_definitions_page, query, limit) do
    matches_page = initial_value_matches_page(project_id, query, limit)

    matches =
      matches_page.items
      |> Enum.map(&definition_hit(&1, :initial))
      |> Enum.sort_by(&sort_key/1)

    {matches, matches_page.truncated}
  end

  defp predicate_fallback_page(suggestions_page, query, limit) do
    items =
      suggestions_page.items
      |> Enum.map(&definition_completion_hit(&1, query, :suggestion))
      |> Enum.sort_by(&sort_key/1)

    page = variable_page(items, limit, suggestions_page.truncated)

    if items == [],
      do: page,
      else: Map.put(page, :fallback, :qualified_references)
  end

  defp variable_page(items, limit, truncated) do
    %{
      mode: :variables,
      items: Enum.take(items, limit),
      truncated: truncated or length(items) > limit
    }
  end

  defp definition_hit(definition, group, action \\ nil) do
    %{
      id: "variable-definition:#{definition.block_id}:#{definition.row_id || 0}:#{definition.column_id || 0}",
      group: group,
      kind: :definition,
      type: :sheet,
      label: definition.qualified_ref,
      context: definition_context(definition),
      action:
        action ||
          %{
            kind: :navigate,
            destination: %{
              type: :sheet,
              id: definition.sheet_id,
              focus: definition_focus(definition)
            }
          },
      meta: %{variable_type: definition.block_type}
    }
  end

  defp definition_completion_hit(definition, query, group \\ :owner) do
    definition_hit(
      definition,
      group,
      %{kind: :complete, value: "$#{definition.qualified_ref}#{predicate_suffix(query)}"}
    )
  end

  defp usage_hit(usage) do
    %{
      id: "variable-usage:#{usage.reference_id}",
      group: usage_group(usage),
      kind: usage_kind(usage),
      type: usage.container_type,
      label: source_label(usage),
      context: usage.container_name,
      action: %{
        kind: :navigate,
        destination: %{
          type: usage.container_type,
          id: usage.container_id,
          focus: usage_focus(usage)
        }
      },
      meta: %{
        source_type: usage.source_type,
        source_kind: usage.source_kind,
        stale: usage.stale
      }
    }
  end

  defp occurrence_matches?(
         %{semantic: :write, operator: operator, value_type: value_type, operand: operand},
         definition,
         %VariableQuery{} = query,
         string_aliases
       ) do
    predicate_type_supported?(definition.block_type, query.operator) and
      value_type != "variable_ref" and
      write_operator_matches?(operator, query.operator) and
      operand_matches?(
        definition.block_type,
        operand,
        query.operator,
        query.literal,
        string_aliases
      )
  end

  defp occurrence_matches?(
         %{semantic: :condition, operator: operator, operand: operand},
         definition,
         %VariableQuery{} = query,
         string_aliases
       ) do
    predicate_type_supported?(definition.block_type, query.operator) and
      condition_operator_matches?(operator, query.operator, query.literal) and
      condition_operand_matches?(
        definition.block_type,
        operator,
        operand,
        query.operator,
        query.literal,
        string_aliases
      )
  end

  defp occurrence_matches?(_usage, _definition, _query, _string_aliases), do: false

  defp write_operator_matches?("set", :equal), do: true
  defp write_operator_matches?("set_if_unset", :equal), do: true
  defp write_operator_matches?("set_true", :equal), do: true
  defp write_operator_matches?("set_false", :equal), do: true
  defp write_operator_matches?("clear", :equal), do: true

  defp write_operator_matches?(operator, query_operator)
       when operator in ["set", "set_if_unset"] and query_operator in [:contains, :not_contains], do: true

  defp write_operator_matches?("add", :add), do: true
  defp write_operator_matches?("subtract", :subtract), do: true
  defp write_operator_matches?(_operator, _query_operator), do: false

  defp condition_operator_matches?("equals", :equal, _literal), do: true
  defp condition_operator_matches?("is_true", :equal, literal), do: normalized_boolean(literal) == "true"
  defp condition_operator_matches?("is_false", :equal, literal), do: normalized_boolean(literal) == "false"
  defp condition_operator_matches?("not_equals", :not_equal, _literal), do: true
  defp condition_operator_matches?("contains", :contains, _literal), do: true
  defp condition_operator_matches?("not_contains", :not_contains, _literal), do: true
  defp condition_operator_matches?("greater_than", :greater_than, _literal), do: true

  defp condition_operator_matches?("greater_than_or_equal", :greater_than_or_equal, _literal), do: true

  defp condition_operator_matches?("less_than", :less_than, _literal), do: true
  defp condition_operator_matches?("before", :less_than, _literal), do: true
  defp condition_operator_matches?("less_than_or_equal", :less_than_or_equal, _literal), do: true
  defp condition_operator_matches?("after", :greater_than, _literal), do: true
  defp condition_operator_matches?(_operator, _query_operator, _literal), do: false

  defp condition_operand_matches?(_type, operator, _operand, _query_operator, _literal, _aliases)
       when operator in ["is_true", "is_false"], do: true

  defp condition_operand_matches?(type, _operator, operand, query_operator, literal, aliases) do
    operand_operator =
      if query_operator == :not_contains,
        do: :contains,
        else: query_operator

    operand_matches?(type, operand, operand_operator, literal, aliases)
  end

  defp operand_matches?(_type, operand, _operator, _literal, _aliases)
       when is_nil(operand) or is_map(operand) or is_list(operand), do: false

  defp operand_matches?(type, operand, operator, literal, aliases)
       when type in ["text", "rich_text", "select"] and is_binary(operand) do
    normalized_operand = normalize_string_operand(operand)
    normalized_literal = literal |> unquote_literal() |> normalize_string_operand()

    contains? =
      normalized_literal != "" and
        (normalized_operand in aliases or String.contains?(normalized_operand, normalized_literal))

    case operator do
      :contains -> contains?
      :not_contains -> normalized_literal != "" and not contains?
      _other -> normalized_operand in aliases
    end
  end

  defp operand_matches?(type, operand, _operator, literal, _aliases)
       when is_binary(operand) or is_number(operand) or is_boolean(operand) do
    with {:ok, expected} <- typed_literal(type, literal),
         {:ok, actual} <- typed_literal(type, to_string(operand)) do
      actual == expected
    else
      :error -> false
    end
  end

  defp operand_matches?(_type, _operand, _operator, _literal, _aliases), do: false

  defp typed_literal("number", literal) do
    case Float.parse(literal) do
      {value, ""} -> {:ok, value}
      _invalid -> :error
    end
  end

  defp typed_literal("boolean", literal) do
    case normalized_boolean(literal) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _invalid -> :error
    end
  end

  defp typed_literal("date", literal) do
    literal = unquote_literal(literal)

    case Date.from_iso8601(literal) do
      {:ok, date} -> {:ok, date}
      _invalid -> :error
    end
  end

  defp typed_literal(_string_like, literal), do: {:ok, unquote_literal(literal)}

  defp unquote_literal(<<"\"", rest::binary>>) do
    if String.ends_with?(rest, "\"") do
      binary_part(rest, 0, byte_size(rest) - 1)
    else
      "\"" <> rest
    end
  end

  defp unquote_literal(literal), do: literal

  defp normalized_boolean(literal) do
    literal
    |> unquote_literal()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_string_operand(operand) do
    operand
    |> String.trim()
    |> String.normalize(:nfc)
    |> String.downcase()
  end

  defp definition_context(%{table_name: nil} = definition), do: definition.sheet_name

  defp definition_context(definition) do
    "#{definition.sheet_name} · #{definition.table_name} · #{definition.row_name} · #{definition.column_name}"
  end

  defp definition_focus(%{table_name: nil, block_id: block_id}), do: %{type: :block, id: block_id}

  defp definition_focus(definition) do
    %{
      type: :cell,
      block_id: definition.block_id,
      row_id: definition.row_id,
      column_id: definition.column_id
    }
  end

  defp usage_focus(%{source_type: :flow_node, source_id: id}), do: %{type: :node, id: id}
  defp usage_focus(%{source_type: :scene_pin, source_id: id}), do: %{type: :pin, id: id}
  defp usage_focus(%{source_type: :scene_zone, source_id: id}), do: %{type: :zone, id: id}
  defp usage_focus(%{source_type: :scene_ambient_flow}), do: nil

  defp usage_focus(%{source_type: :table_formula} = usage) do
    %{
      type: :cell,
      block_id: usage.block_id,
      row_id: usage.row_id,
      column_id: usage.column_id
    }
  end

  defp usage_focus(%{source_type: :block, source_id: id}), do: %{type: :block, id: id}
  defp usage_focus(_usage), do: nil

  defp source_label(%{source_label: label}) when is_binary(label) and label != "", do: label
  defp source_label(usage), do: "#{usage.container_name} · #{humanize(usage.source_kind)}"

  defp usage_group(%{semantic: :condition}), do: :condition
  defp usage_group(%{kind: "write"}), do: :write
  defp usage_group(_usage), do: :read

  defp usage_kind(%{semantic: :condition, operator: operator}), do: condition_kind(operator)
  defp usage_kind(%{semantic: :write, operator: operator}), do: write_kind(operator)

  defp usage_kind(%{source_type: :table_formula}), do: :formula_read
  defp usage_kind(%{kind: "read"}), do: :read
  defp usage_kind(%{kind: "write"}), do: :write

  defp condition_kind("equals"), do: :condition_equals
  defp condition_kind("not_equals"), do: :condition_not_equals
  defp condition_kind("contains"), do: :condition_contains
  defp condition_kind("not_contains"), do: :condition_not_contains
  defp condition_kind("greater_than"), do: :condition_greater_than
  defp condition_kind("greater_than_or_equal"), do: :condition_greater_than_or_equal
  defp condition_kind("less_than"), do: :condition_less_than
  defp condition_kind("less_than_or_equal"), do: :condition_less_than_or_equal
  defp condition_kind("before"), do: :condition_before
  defp condition_kind("after"), do: :condition_after
  defp condition_kind("is_true"), do: :condition_is_true
  defp condition_kind("is_false"), do: :condition_is_false
  defp condition_kind(_operator), do: :condition

  defp write_kind("set"), do: :write_set
  defp write_kind("set_if_unset"), do: :write_set_if_unset
  defp write_kind("set_true"), do: :write_set_true
  defp write_kind("set_false"), do: :write_set_false
  defp write_kind("clear"), do: :write_clear
  defp write_kind("add"), do: :write_add
  defp write_kind("subtract"), do: :write_subtract
  defp write_kind(_operator), do: :write

  defp sort_key(hit), do: {group_rank(hit.group), String.downcase(hit.label), hit.id}
  defp group_rank(:owner), do: 0
  defp group_rank(:initial), do: 1
  defp group_rank(:read), do: 2
  defp group_rank(:condition), do: 3
  defp group_rank(:write), do: 4
  defp group_rank(:suggestion), do: 5

  defp exact_definition_filter(reference) do
    if String.contains?(reference, "."),
      do: {:qualified, reference},
      else: {:variable, reference}
  end

  defp load_exact_definitions(project_id, %VariableQuery{reference: reference}) do
    Sheets.search_variable_definitions(
      project_id,
      exact_definition_filter(reference),
      limit: @max_limit
    )
  end

  defp initial_value_matches_page(
         project_id,
         %VariableQuery{reference: reference, operator: operator, literal: literal},
         limit
       ) do
    Sheets.search_variable_initial_value_matches(
      project_id,
      exact_definition_filter(reference),
      operator,
      literal,
      limit: limit
    )
  end

  defp predicate_suffix(%VariableQuery{operator: nil}), do: ""

  defp predicate_suffix(%VariableQuery{operator: operator, literal: literal}) do
    " #{operator_symbol(operator)} #{literal}"
  end

  defp operator_symbol(:add), do: "+="
  defp operator_symbol(:subtract), do: "-="
  defp operator_symbol(:greater_than_or_equal), do: ">="
  defp operator_symbol(:less_than_or_equal), do: "<="
  defp operator_symbol(:not_equal), do: "!="
  defp operator_symbol(:not_contains), do: "!~"
  defp operator_symbol(:equal), do: "="
  defp operator_symbol(:contains), do: "~"
  defp operator_symbol(:greater_than), do: ">"
  defp operator_symbol(:less_than), do: "<"

  defp predicate_type_supported?(type, operator) when operator in [:contains, :not_contains],
    do: type in ["text", "rich_text", "select"]

  defp predicate_type_supported?(type, _operator), do: type in @predicate_types

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end
