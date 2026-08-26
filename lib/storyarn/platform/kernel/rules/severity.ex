defmodule Storyarn.Platform.Shared.Severity do
  @moduledoc """
  The single ordering of the health severity catalog.

  Health findings carry `:error | :warning | :info`. Everything that sorts them
  needs the same three-line ordering. UI consumers rank the **strings** that
  cross the LiveVue boundary while domain consumers rank the **atoms** on the
  server side. `rank/1` accepts both so neither side has to normalise before
  sorting.

  It is strict on purpose. Severity is a closed catalog produced by
  `severity_for/1` in the health checkers, so a value outside it means the caller
  built a finding wrong — silently sorting it last would hide that. Two of the
  five copies already raised on unknown input; the other two had a defensive
  catch-all that no live code path could reach.

      Enum.sort_by(findings, &Severity.rank(&1.severity))
  """

  @catalog [:error, :warning, :info]

  @doc """
  Sort key for a severity: `0` for `:error`, `1` for `:warning`, `2` for `:info`.

  Accepts the atom and the string spelling of each.

  Raises `ArgumentError` for anything else.
  """
  @spec rank(atom() | String.t()) :: 0..2
  def rank(:error), do: 0
  def rank(:warning), do: 1
  def rank(:info), do: 2
  def rank("error"), do: 0
  def rank("warning"), do: 1
  def rank("info"), do: 2

  def rank(other) do
    raise ArgumentError,
          "unknown severity #{inspect(other)}; expected one of #{inspect(@catalog)} (atom or string)"
  end

  @doc """
  The severity catalog, in rank order.
  """
  @spec catalog() :: [atom()]
  def catalog, do: @catalog
end
