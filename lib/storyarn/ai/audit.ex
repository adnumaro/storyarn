defmodule Storyarn.AI.Audit do
  @moduledoc """
  Records AI integration lifecycle events for security investigations.

  Callers pass a plain `user_id`, provider identifier, action atom, and a
  metadata map. Metadata MUST NOT contain key material — see
  `Storyarn.AI.AuditEntry`.
  """

  alias Storyarn.AI.AuditEntry
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Insert an audit row. Returns `{:ok, entry}` or `{:error, changeset}`.

  Failures are non-fatal for the caller — the caller may choose to log the
  error and proceed, since audit is defense-in-depth, not the primary source
  of truth.
  """
  @spec log(integer() | nil, atom() | String.t(), AuditEntry.action(), map()) ::
          {:ok, AuditEntry.t()} | {:error, Ecto.Changeset.t()}
  def log(user_id, provider, action, metadata \\ %{}) do
    attrs = %{
      user_id: user_id,
      provider: to_string(provider),
      action: Atom.to_string(action),
      metadata: metadata
    }

    %AuditEntry{inserted_at: TimeHelpers.now()}
    |> AuditEntry.changeset(attrs)
    |> Repo.insert()
  end
end
