defmodule Storyarn.AI.Audit do
  @moduledoc """
  Records AI integration lifecycle events for security investigations.

  Metadata is sanitized before insert: only whitelisted keys with scalar
  values survive, so no caller — present or future — can persist key material
  or arbitrary payloads through this API.
  """

  alias Storyarn.AI.AuditEntry
  alias Storyarn.Repo

  # Only these metadata keys are ever persisted. Extend deliberately.
  @allowed_metadata_keys [
    :reason,
    :unexpected_status,
    :integration_id,
    :workspace_id,
    :assignment_id,
    :preference_id,
    :slot,
    :model,
    "reason",
    "unexpected_status",
    "integration_id",
    "workspace_id",
    "assignment_id",
    "preference_id",
    "slot",
    "model"
  ]
  @max_value_bytes 200

  @doc """
  Insert an audit row. Returns `{:ok, entry}` or `{:error, changeset}`.

  Credential-mutation callers include this insert in the same transaction so
  the lifecycle change and audit cannot diverge. Validation-failure callers
  have no credential mutation to roll back. `user_id` is stored twice: as a
  nilifiable FK and as the immutable `actor_id` snapshot.
  """
  @spec log(integer(), atom() | String.t(), AuditEntry.action(), map()) ::
          {:ok, AuditEntry.t()} | {:error, Ecto.Changeset.t()}
  def log(user_id, provider, action, metadata \\ %{}) do
    attrs = %{
      user_id: user_id,
      actor_id: user_id,
      provider: to_string(provider),
      action: Atom.to_string(action),
      metadata: sanitize_metadata(metadata)
    }

    %AuditEntry{}
    |> AuditEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Exposed for tests — strips non-whitelisted keys and non-scalar values."
  @spec sanitize_metadata(map()) :: map()
  def sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.take(@allowed_metadata_keys)
    |> Map.new(fn {key, value} -> {to_string(key), sanitize_value(value)} end)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  def sanitize_metadata(_metadata), do: %{}

  defp sanitize_value(value) when is_binary(value) and byte_size(value) <= @max_value_bytes, do: value

  defp sanitize_value(value) when is_integer(value), do: value
  defp sanitize_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp sanitize_value(_value), do: nil
end
