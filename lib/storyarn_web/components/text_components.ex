defmodule StoryarnWeb.Components.TextComponents do
  @moduledoc """
  Typography helpers for rendered text.
  """

  alias Storyarn.Shared.HtmlSanitizer

  import Phoenix.HTML, only: [html_escape: 1, raw: 1, safe_to_string: 1]

  @doc """
  Prevents widow words by joining the final two words with a non-breaking space.

  Whitespace is normalized, which is appropriate for headings and short UI copy.
  """
  @spec widont(String.t()) :: Phoenix.HTML.safe()
  def widont(text) when is_binary(text) do
    case String.split(text, ~r/\s+/u, trim: true) do
      [] ->
        safe_raw("")

      [single] ->
        single |> html_escape() |> safe_to_string() |> safe_raw()

      words ->
        {leading, [penultimate, last]} = Enum.split(words, length(words) - 2)

        leading_html =
          leading
          |> Enum.map_join(" ", &escape_segment/1)

        trailing_html = escape_segment(penultimate) <> "&nbsp;" <> escape_segment(last)

        case leading_html do
          "" -> safe_raw(trailing_html)
          _ -> safe_raw(leading_html <> " " <> trailing_html)
        end
    end
  end

  defp escape_segment(segment), do: segment |> html_escape() |> safe_to_string()

  defp safe_raw(html), do: html |> HtmlSanitizer.sanitize_html() |> raw()
end
