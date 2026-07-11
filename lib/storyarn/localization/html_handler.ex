defmodule Storyarn.Localization.HtmlHandler do
  @moduledoc false

  @placeholder_regex ~r/\{[^{}\r\n]+\}/

  @doc """
  Pre-processes rich text before sending to translation API.
  Wraps variable placeholders like `{variable_name}` in `<span translate="no">`
  so they are preserved by the translation service.
  """
  @spec pre_translate(String.t()) :: String.t()
  def pre_translate(text) when is_binary(text) do
    # Wrap {placeholder} patterns in translate="no" spans
    Regex.replace(@placeholder_regex, text, fn full_match ->
      ~s(<span translate="no">#{full_match}</span>)
    end)
  end

  def pre_translate(text), do: text

  @doc """
  Post-processes translated text after receiving from translation API.
  Unwraps the `<span translate="no">` wrappers added by `pre_translate/1`.
  """
  @spec post_translate(String.t()) :: String.t()
  def post_translate(text) when is_binary(text) do
    # Unwrap the translate="no" spans, keeping the inner content
    Regex.replace(
      ~r/<span translate="no">\s*(\{[^}]+\})\s*<\/span>/,
      text,
      "\\1"
    )
  end

  def post_translate(text), do: text

  @doc "Returns placeholders in occurrence order, including duplicates."
  @spec placeholders(String.t() | nil) :: [String.t()]
  def placeholders(text) when is_binary(text), do: @placeholder_regex |> Regex.scan(text) |> List.flatten()
  def placeholders(_text), do: []

  @doc "Ensures a translation preserves exactly the source placeholder multiset."
  @spec validate_placeholders(String.t() | nil, String.t() | nil) ::
          :ok | {:error, %{missing: [String.t()], extra: [String.t()]}}
  def validate_placeholders(source_text, translated_text) do
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

  @doc """
  Determines whether a text field contains HTML and should use tag_handling.
  """
  @spec html?(String.t()) :: boolean()
  def html?(text) when is_binary(text) do
    Regex.match?(~r/<\/?[A-Za-z][^>]*>/, text)
  end

  def html?(_), do: false

  defp frequency_difference(left, right) do
    Enum.flat_map(left, fn {placeholder, count} ->
      List.duplicate(placeholder, max(count - Map.get(right, placeholder, 0), 0))
    end)
  end
end
