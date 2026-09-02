defmodule Storyarn.Projects.Imports.ImportedVariableRewriter do
  @moduledoc """
  Rewrites variable references after imported Sheet shortcuts are resolved.

  This rule understands Storyarn's normalized node fields, not any external
  source format. Format adapters may perform an additional source-aware render
  after this structural pass.
  """

  @spec rewrite_node_data(map(), String.t(), %{optional(String.t()) => String.t()}) :: map()
  def rewrite_node_data(node_data, "annotation", _renames), do: node_data

  def rewrite_node_data(node_data, "dialogue", renames) do
    node_data
    |> rewrite_variable_shortcuts(renames)
    |> rewrite_dialogue_interpolations(renames)
  end

  def rewrite_node_data(node_data, _type, renames), do: rewrite_variable_shortcuts(node_data, renames)

  defp rewrite_variable_shortcuts(node_data, renames) when renames == %{} or not is_map(node_data), do: node_data
  defp rewrite_variable_shortcuts(node_data, renames), do: deep_rewrite_refs(node_data, renames)

  defp deep_rewrite_refs(%{} = map, renames) do
    Map.new(map, fn
      {key, value} when key in ["sheet", "value_sheet"] and is_binary(value) ->
        {key, Map.get(renames, value, value)}

      {"condition" = key, value} when is_binary(value) ->
        {key, rewrite_encoded_condition(value, renames)}

      {"variable_ref" = key, value} when is_binary(value) ->
        {key, rewrite_bare_variable_ref(value, renames)}

      {key, value} ->
        {key, deep_rewrite_refs(value, renames)}
    end)
  end

  defp deep_rewrite_refs(list, renames) when is_list(list), do: Enum.map(list, &deep_rewrite_refs(&1, renames))
  defp deep_rewrite_refs(value, _renames), do: value

  defp rewrite_encoded_condition(value, renames) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) ->
        decoded |> deep_rewrite_refs(renames) |> Jason.encode!()

      _not_structured ->
        value
    end
  end

  defp rewrite_dialogue_interpolations(data, renames) when renames == %{} or not is_map(data), do: data

  defp rewrite_dialogue_interpolations(data, renames) do
    data
    |> Map.update("text", nil, &rewrite_semantic_interpolations(&1, renames, :dialogue))
    |> Map.update("responses", [], fn
      responses when is_list(responses) ->
        Enum.map(responses, fn
          response when is_map(response) ->
            Map.update(response, "text", nil, &rewrite_semantic_interpolations(&1, renames, :response))

          response ->
            response
        end)

      responses ->
        responses
    end)
  end

  defp rewrite_semantic_interpolations(value, renames, mode) when is_binary(value) do
    {prefix, suffix} = if(mode == :dialogue, do: {"{", "}"}, else: {"$", ""})

    alternation =
      renames
      |> Map.keys()
      |> Enum.sort_by(&byte_size/1, :desc)
      |> Enum.map_join("|", &Regex.escape/1)

    pattern =
      Regex.compile!(
        Regex.escape(prefix) <> "(" <> alternation <> ")\\.([A-Za-z_][A-Za-z0-9_.]*)" <> Regex.escape(suffix)
      )

    Regex.replace(pattern, value, fn _match, imported, variable ->
      prefix <> Map.fetch!(renames, imported) <> "." <> variable <> suffix
    end)
  end

  defp rewrite_semantic_interpolations(value, _renames, _mode), do: value

  defp rewrite_bare_variable_ref(value, renames) do
    case String.split(value, ".", parts: 2) do
      [shortcut, rest] -> Map.get(renames, shortcut, shortcut) <> "." <> rest
      _no_prefix -> value
    end
  end
end
