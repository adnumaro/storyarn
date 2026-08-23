defmodule Storyarn.Shared.StringUtils do
  @moduledoc """
  Small string predicates that were copied across serializers, health checkers
  and dashboards.

  ## `blank?/1` vs the trimming variants

  `blank?/1` here is the *exact* reading: `nil` or `""`. It replaces eight
  byte-equivalent private copies (the five export serializers, the export
  validator's `nil_or_empty?/1`, `Flows.HealthChecker`, `Flows.StructuralAnalysis`).

  Three other modules define a `blank?/1` that also trims:

    * the Sheets health checker
    * the Scenes health checker
    * `Storyarn.Localization.GlossarySync` (which additionally raises on a
      non-binary, non-nil term)

  Those are **deliberately not** folded in here: for them a whitespace-only sheet
  block or scene label counts as empty, and quietly changing that would change
  which findings the health sweeps report. This module offers no trimming
  `blank?/1` variant on purpose — a second, subtly different predicate sitting
  next to this one is exactly how the copies diverged in the first place.

  ## `present_label/2`

  The dashboard/health label fallback, byte-identical in four modules. It trims to
  decide presence but returns the original value untouched, so a label is never
  silently reformatted.
  """

  @doc """
  True when the value is `nil` or the empty string. Does **not** trim.

  Any other term — numbers, `false`, collections — is not blank.
  """
  @spec blank?(term()) :: boolean()
  def blank?(nil), do: true
  def blank?(""), do: true
  def blank?(_value), do: false

  @doc """
  Returns `value` when it carries a non-whitespace label, otherwise `fallback`.

  The returned value is not trimmed — trimming only decides presence.
  """
  @spec present_label(term(), label) :: term() | label when label: term()
  def present_label(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  def present_label(_value, fallback), do: fallback
end
