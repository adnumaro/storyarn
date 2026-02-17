defmodule Storyarn.Localization.HtmlHandler do
  @moduledoc false

  @doc """
  Pre-processes rich text before sending to translation API.
  Wraps variable placeholders like `{variable_name}` in `<span translate="no">`
  so they are preserved by the translation service.
  """
  @spec pre_translate(String.t()) :: String.t()
  def pre_translate(text) when is_binary(text) do
    # Wrap {placeholder} patterns in translate="no" spans
    Regex.replace(~r/\{([^}]+)\}/, text, fn full_match, _inner ->
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

  @doc """
  Determines whether a text field contains HTML and should use tag_handling.
  """
  @spec html?(String.t()) :: boolean()
  def html?(text) when is_binary(text) do
    String.contains?(text, "<")
  end

  def html?(_), do: false
end
