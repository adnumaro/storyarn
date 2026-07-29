defmodule Storyarn.GlobalSearch.ReferencePattern do
  @moduledoc false

  @max_length 100
  @identifier ~S([a-zA-Z0-9_][a-zA-Z0-9_-]*)
  @partial ~S([a-zA-Z0-9_-]+)
  @global_partial Regex.compile!("^\\?(#{@partial})$")
  @sheet_all Regex.compile!("^(#{@identifier}(?:\\.#{@identifier})*)\\.\\?$")
  @deep_exact Regex.compile!("^sheets\\.\\*\\*\\.(#{@identifier})$")
  @deep_partial Regex.compile!("^sheets\\.\\*\\*\\.\\?(#{@partial})$")
  @qualified Regex.compile!("^#{@identifier}(?:\\.#{@identifier})+$")
  @captured_filters [
    {@deep_partial, :variable_contains},
    {@deep_exact, :variable},
    {@global_partial, :variable_contains},
    {@sheet_all, :sheet}
  ]

  @type filter ::
          {:qualified, String.t()}
          | {:sheet, String.t()}
          | {:variable, String.t()}
          | {:variable_contains, String.t()}

  @spec parse(String.t()) :: {:ok, filter()} | {:error, :invalid_request}
  def parse(pattern) when is_binary(pattern) do
    if valid_pattern?(pattern), do: parse_valid_pattern(pattern), else: {:error, :invalid_request}
  end

  def parse(_pattern), do: {:error, :invalid_request}

  defp valid_pattern?(pattern) do
    pattern != "" and pattern == String.trim(pattern) and String.length(pattern) <= @max_length
  end

  defp parse_valid_pattern(pattern) do
    case captured_filter(pattern) do
      nil ->
        if Regex.match?(@qualified, pattern),
          do: {:ok, {:qualified, pattern}},
          else: {:error, :invalid_request}

      filter ->
        {:ok, filter}
    end
  end

  defp captured_filter(pattern) do
    Enum.find_value(@captured_filters, fn {regex, filter} ->
      case Regex.run(regex, pattern, capture: :all_but_first) do
        [value] -> {filter, value}
        nil -> nil
      end
    end)
  end
end
