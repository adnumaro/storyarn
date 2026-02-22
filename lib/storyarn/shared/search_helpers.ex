defmodule Storyarn.Shared.SearchHelpers do
  @moduledoc """
  Shared helpers for LIKE/ILIKE search queries.
  """

  @doc """
  Escapes LIKE wildcard characters in a user-provided search query.

  Prevents `%`, `_`, and `\\` from being interpreted as LIKE wildcards,
  which could otherwise allow users to craft queries matching unintended rows.

  ## Examples

      iex> SearchHelpers.sanitize_like_query("100%")
      "100\\\\%"

      iex> SearchHelpers.sanitize_like_query("foo_bar")
      "foo\\\\_bar"
  """
  @spec sanitize_like_query(String.t()) :: String.t()
  def sanitize_like_query(query) do
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
