defmodule Storyarn.Flows.PlayerText do
  @moduledoc """
  Interprets authored player text references against evaluator variables.

  Rich-text rendering is adapter-driven: this module recognizes references and
  resolves their values, while the caller decides how resolved or missing values
  are escaped and represented in HTML.
  """

  @type resolution :: {:value, String.t(), term()} | {:missing, String.t()}
  @type renderer :: (resolution() -> String.t())
  @type reference_renderer :: (String.t() -> String.t())

  @variable_span ~r/<span\s[^>]*?data-ref="([^"]+)"[^>]*>[^<]*<\/span>/
  @brace_reference ~r/\{([a-zA-Z0-9_.]+)\}/
  @plain_reference ~r/\$([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+)/

  @doc "Resolves rich-text variable markers using an adapter-provided renderer."
  @spec interpolate_rich_text(String.t(), map(), renderer()) :: String.t()
  def interpolate_rich_text("", _variables, _renderer), do: ""

  def interpolate_rich_text(text, variables, renderer)
      when is_binary(text) and is_map(variables) and is_function(renderer, 1) do
    text
    |> replace_variable_spans(variables, renderer)
    |> replace_brace_references(variables, renderer)
  end

  @doc "Maps authored rich-text references without resolving their runtime values."
  @spec map_rich_text_references(String.t(), reference_renderer()) :: String.t()
  def map_rich_text_references("", _renderer), do: ""

  def map_rich_text_references(text, renderer) when is_binary(text) and is_function(renderer, 1) do
    text
    |> map_variable_spans(renderer)
    |> map_brace_references(renderer)
  end

  @doc "Interpolates `$namespace.variable` references in player response text."
  @spec interpolate_response_text(String.t(), map()) :: String.t()
  def interpolate_response_text("", _variables), do: ""

  def interpolate_response_text(text, variables) when is_binary(text) and is_map(variables) do
    Regex.replace(@plain_reference, text, fn _full, ref ->
      case resolve(ref, variables) do
        {:value, _ref, value} -> format_value(value)
        {:missing, _ref} -> "[$#{ref}]"
      end
    end)
  end

  @doc "Formats a resolved player variable without presentation-specific escaping."
  @spec format_value(term()) :: String.t()
  def format_value(nil), do: "nil"
  def format_value(true), do: "true"
  def format_value(false), do: "false"
  def format_value(value) when is_list(value), do: Enum.join(value, ", ")
  def format_value(value) when is_binary(value), do: value
  def format_value(value), do: to_string(value)

  defp replace_variable_spans(text, variables, renderer) do
    Regex.replace(@variable_span, text, fn full, ref ->
      if String.contains?(full, "variable-ref") do
        variables |> resolve(ref) |> renderer.()
      else
        full
      end
    end)
  end

  defp map_variable_spans(text, renderer) do
    Regex.replace(@variable_span, text, fn full, ref ->
      if String.contains?(full, "variable-ref"), do: renderer.(ref), else: full
    end)
  end

  defp replace_brace_references(text, variables, renderer) do
    Regex.replace(@brace_reference, text, fn _full, ref ->
      variables |> resolve(ref) |> renderer.()
    end)
  end

  defp map_brace_references(text, renderer) do
    Regex.replace(@brace_reference, text, fn _full, ref -> renderer.(ref) end)
  end

  defp resolve(variables, ref) when is_map(variables), do: resolve(ref, variables)

  defp resolve(ref, variables) do
    case Map.get(variables, ref) do
      %{value: value} -> {:value, ref, value}
      nil -> {:missing, ref}
    end
  end
end
