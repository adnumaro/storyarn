defmodule Storyarn.Projects.Severity do
  @moduledoc """
  The single ordering of the health severity catalog.

  Project-owned copy of the retired shared ordering (ENG-92): health findings
  carry `:error | :warning | :info` and everything that sorts them needs the
  same three-line ordering. `rank/1` accepts the atom and string spellings.

  It is strict on purpose. Severity is a closed catalog, so a value outside it
  means the caller built a finding wrong — silently sorting it last would hide
  that.

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
