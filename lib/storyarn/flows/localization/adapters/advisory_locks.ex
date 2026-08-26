defmodule Storyarn.Flows.Localization.Adapters.AdvisoryLocks do
  @moduledoc """
  PostgreSQL advisory-lock adapter used by Flow localization reconciliation.

  The caller owns the surrounding transaction and the domain decision about
  which resources must be serialized. This module owns only the provider-
  specific lock statements.
  """

  alias Storyarn.Repo

  @spec lock_exclusive!(String.t(), term()) :: Postgrex.Result.t()
  def lock_exclusive!(namespace, id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended(concat($1::text, ':', $2::text), 0))",
      [namespace, to_string(id)]
    )
  end

  @spec lock_shared!(String.t(), term()) :: Postgrex.Result.t()
  def lock_shared!(namespace, id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock_shared(hashtextextended(concat($1::text, ':', $2::text), 0))",
      [namespace, to_string(id)]
    )
  end
end
