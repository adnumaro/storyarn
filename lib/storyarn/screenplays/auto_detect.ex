defmodule Storyarn.Screenplays.AutoDetect do
  @moduledoc """
  Auto-detects screenplay element type from text content patterns.

  Returns the detected type as a string, or `nil` if no pattern matches
  (meaning the current type should be kept).
  """

  alias Storyarn.Screenplays.ContentUtils

  @doc """
  Detects the element type based on content patterns.

  Strips HTML before matching so TipTap content is handled correctly.

  ## Examples

      iex> detect_type("INT. LIVING ROOM - DAY")
      "scene_heading"

      iex> detect_type("CUT TO:")
      "transition"

      iex> detect_type("JOHN")
      "character"

      iex> detect_type("(whispering)")
      "parenthetical"

      iex> detect_type("He walks away.")
      nil
  """
  @spec detect_type(String.t()) :: String.t() | nil
  def detect_type(content) do
    trimmed = content |> ContentUtils.strip_html() |> String.trim()

    cond do
      trimmed == "" ->
        nil

      scene_heading?(trimmed) ->
        "scene_heading"

      known_transition?(trimmed) ->
        "transition"

      generic_transition?(trimmed) ->
        "transition"

      parenthetical?(trimmed) ->
        "parenthetical"

      character_name?(trimmed) ->
        "character"

      true ->
        nil
    end
  end

  # INT. / EXT. / INT./EXT. / I/E. prefixes
  defp scene_heading?(text) do
    Regex.match?(~r/^(INT\.|EXT\.|INT\.\/EXT\.|I\/E\.?|EST\.)\s/i, text)
  end

  # Well-known transitions
  @known_transitions ["FADE IN:", "FADE OUT.", "FADE TO BLACK.", "INTERCUT:"]
  defp known_transition?(text), do: text in @known_transitions

  # Pattern: ALL CAPS + "TO:" at end (e.g. "CUT TO:", "DISSOLVE TO:")
  defp generic_transition?(text) do
    Regex.match?(~r/^[A-Z\s]+TO:$/, text)
  end

  # Wrapped in parentheses
  defp parenthetical?(text) do
    Regex.match?(~r/^\(.*\)$/, text)
  end

  # ALL CAPS name, optionally with (V.O.) or (O.S.) extension, under 50 chars
  # Must check AFTER transitions and parentheticals to avoid false positives
  defp character_name?(text) do
    String.length(text) < 50 and
      Regex.match?(~r/^[A-Z][A-Z\s\.\-']+(\s*\([^)]+\))*$/, text)
  end
end
