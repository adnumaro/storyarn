defmodule Storyarn.Platform.CommandPalette.Adapters.ActorLock do
  @moduledoc """
  PostgreSQL advisory-lock adapter for idempotent palette mutations.

  The namespace and hash range are stable parts of the existing lock protocol.
  The caller owns the surrounding transaction and operation ordering.
  """

  alias Storyarn.Repo

  @lock_namespace 981_003
  @max_lock_key 2_147_483_647

  @spec lock!(term()) :: :ok
  def lock!(user_id) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [
      @lock_namespace,
      :erlang.phash2(user_id, @max_lock_key)
    ])

    :ok
  end
end
