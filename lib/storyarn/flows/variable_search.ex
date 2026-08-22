defmodule Storyarn.Flows.VariableSearch do
  @moduledoc """
  Flow-owned search and projection rules for the editor's variable catalog.

  The persistence-backed catalog exposes descriptors used by the Flow runtime.
  This module turns those descriptors into the two bounded search contracts
  consumed by the editor, keeping variable references and matching semantics
  inside the Flows bounded context.
  """

  @suggestion_limit 20
  @picker_default_limit 100
  @picker_max_limit 100

  @type descriptor :: map()
  @type suggestion :: %{
          ref: String.t(),
          sheet_name: String.t() | nil,
          variable_name: String.t() | nil,
          block_type: String.t() | nil
        }
  @type picker_option :: %{id: String.t(), name: String.t()}

  @doc """
  Searches variable descriptors for the dialogue-editor suggestion menu.

  Matching is case-insensitive across the canonical Flow variable reference
  and the owning Sheet display name. Results retain catalog order.
  """
  @spec suggestions([descriptor()], String.t()) :: [suggestion()]
  def suggestions(variables, query) when is_list(variables) and is_binary(query) do
    normalized_query = normalize(query)

    variables
    |> Enum.filter(&suggestion_matches?(&1, normalized_query))
    |> Enum.take(@suggestion_limit)
    |> Enum.map(&suggestion/1)
  end

  @doc """
  Builds the Flow editor's bounded variable-picker page.

  The selected option remains visible when it matches the active query, even
  if it falls outside the requested page. The boolean reports whether matching
  results exist beyond the bounded page.
  """
  @spec picker_options([descriptor()], keyword()) :: {[picker_option()], boolean()}
  def picker_options(variables, opts \\ []) when is_list(variables) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, @picker_default_limit) |> bounded_limit()
    query = opts |> Keyword.get(:query, "") |> normalize_query()
    selected_id = Keyword.get(opts, :selected_id)
    options = Enum.map(variables, &picker_option/1)

    matches = Enum.filter(options, &picker_search_matches?(&1, query))
    page = Enum.take(matches, limit)
    has_more = length(matches) > limit
    selected = selected_option(options, selected_id)

    {maybe_include_selected(page, selected, query), has_more}
  end

  defp suggestion_matches?(variable, query) do
    normalize(reference(variable)) =~ query or
      normalize(field(variable, :sheet_name)) =~ query
  end

  defp suggestion(variable) do
    %{
      ref: reference(variable),
      sheet_name: field(variable, :sheet_name),
      variable_name: field(variable, :variable_name),
      block_type: field(variable, :block_type)
    }
  end

  defp picker_option(variable) do
    ref = field(variable, :ref) || reference(variable)
    label = field(variable, :label) || ref

    %{id: ref, name: label}
  end

  defp reference(variable) do
    [field(variable, :sheet_shortcut), field(variable, :variable_name)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(".")
  end

  defp field(variable, key) when is_map(variable) do
    Map.get(variable, key) || Map.get(variable, Atom.to_string(key))
  end

  defp picker_search_matches?(_option, ""), do: true
  defp picker_search_matches?(option, query), do: normalize(option.name) =~ query

  defp selected_matches?(_option, ""), do: true
  defp selected_matches?(option, query), do: normalize(option.name) =~ normalize(query)

  defp selected_option(_options, nil), do: nil

  defp selected_option(options, selected_id) do
    Enum.find(options, &(to_string(&1.id) == to_string(selected_id)))
  end

  defp maybe_include_selected(items, nil, _query), do: items

  defp maybe_include_selected(items, selected, query) do
    cond do
      not selected_matches?(selected, query) -> items
      Enum.any?(items, &(&1.id == selected.id)) -> items
      true -> [selected | items]
    end
  end

  defp bounded_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @picker_max_limit)

  defp bounded_limit(_limit), do: @picker_default_limit

  defp normalize_query(query) when is_binary(query), do: String.trim(query)
  defp normalize_query(_query), do: ""

  defp normalize(value) when is_binary(value), do: String.downcase(value)
  defp normalize(nil), do: ""
  defp normalize(value), do: value |> to_string() |> String.downcase()
end
