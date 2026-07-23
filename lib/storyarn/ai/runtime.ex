defmodule Storyarn.AI.Runtime do
  @moduledoc """
  Cross-cutting runtime for consumers that call AI providers with a user's key.

  Wraps every provider call with the concerns each consumer would otherwise
  reimplement: active-integration lookup, usage tracking, auto-revocation when
  the provider rejects the key, and telemetry.

  There is deliberately no completion/chat API yet — the first real consumer
  defines that shape (streaming vs. buffered, message format, tool use).
  Until then consumers receive the plaintext key inside `fun` and make their
  own HTTP call.

  ## Contract for `fun`

  `fun` receives the plaintext API key and must return:

    * `{:ok, result}` — success; `last_used_at` is updated.
    * `{:error, :unauthorized}` — the provider rejected the key (401/403).
      The integration is auto-revoked and an `auto_revoked` audit row is
      written; the UI will prompt the user to reconnect.
    * `{:error, reason}` — any other failure; passed through untouched.

  ## Telemetry

  Emits `[:ai, :integration, :call, :start | :stop | :exception]` via
  `:telemetry.span/3` with finite provider and credential-kind metadata. Raw
  user ids are deliberately excluded.
  """

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Integration
  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.Provider
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @type call_result :: {:ok, term()} | {:error, :unauthorized | term()}

  @doc """
  Run `fun` with the user's plaintext API key for `provider`.

  Returns `{:error, :not_connected}` when the user has no active integration
  for the provider; otherwise returns whatever `fun` returns.
  """
  @spec with_personal_integration(User.t() | integer(), Provider.id() | String.t(), (String.t() ->
                                                                                       call_result())) ::
          {:error, :not_connected} | call_result()
  def with_personal_integration(user, provider, fun) when is_function(fun, 1) do
    case IntegrationCrud.get_active(user, provider) do
      nil ->
        {:error, :not_connected}

      %Integration{} = integration ->
        metadata = %{provider: integration.provider, credential_kind: "personal_byok"}

        :telemetry.span([:ai, :integration, :call], metadata, fn ->
          result = fun.(integration.api_key_encrypted)
          record_outcome(integration, result)
          {result, metadata}
        end)
    end
  end

  defp record_outcome(integration, {:ok, _result}) do
    integration
    |> Integration.touch_usage_changeset(TimeHelpers.now())
    |> Repo.update()
  end

  # Conditional revoke: concurrent rejected calls transition the integration
  # exactly once, so only one auto_revoked audit row is ever written.
  defp record_outcome(integration, {:error, :unauthorized}) do
    IntegrationCrud.revoke_active(integration, :auto_revoked)
  end

  defp record_outcome(_integration, _other), do: :ok
end
