defmodule Storyarn.Flows.Versioning.PlaceholderValidator do
  @moduledoc false

  @placeholder_regex ~r/\{[^{}\r\n]+\}/

  def validate(source_text, translated_text) do
    source = source_text |> placeholders() |> Enum.frequencies()
    translated = translated_text |> placeholders() |> Enum.frequencies()

    if source == translated do
      :ok
    else
      {:error,
       %{
         missing: frequency_difference(source, translated),
         extra: frequency_difference(translated, source)
       }}
    end
  end

  defp placeholders(text) when is_binary(text), do: @placeholder_regex |> Regex.scan(text) |> List.flatten()

  defp placeholders(_text), do: []

  defp frequency_difference(left, right) do
    Enum.flat_map(left, fn {placeholder, count} ->
      List.duplicate(placeholder, max(count - Map.get(right, placeholder, 0), 0))
    end)
  end
end
