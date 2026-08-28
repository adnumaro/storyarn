defmodule Storyarn.Platform.RateLimiter do
  @moduledoc """
  Technical rate-limit mechanism using Hammer v7.

  Uses the ETS backend by default, and the Redis backend in production when
  `REDIS_URL` is set (for multi-node support). `config/runtime.exs` is the only
  reader of that variable and resolves it into `:rate_limiter_redis_url`; a
  configured URL is what selects the backend, so the value that makes the choice
  is always the value the backend receives.

  This module deliberately owns no product bucket names, limits or windows.
  Accounts, AI, Workspaces, Projects and application coordinators own those
  policies and call `check/3` with an already namespaced key.

  ## Configuration

  Rate limiting can be disabled for testing:

      config :storyarn, Storyarn.Platform.RateLimiter, enabled: false

  Backend selection is derived from the URL alone (set in runtime.exs for prod):

      config :storyarn, :rate_limiter_redis_url, "redis://host:6379"

  A disabled limiter still returns `:ok`, preserving the established test and
  local-development behavior.
  """
  alias Storyarn.Platform.RateLimiter.ETSBackend
  alias Storyarn.Platform.RateLimiter.RedisBackend

  @doc "Checks one consumer-owned bucket through the configured backend."
  @spec check(String.t(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check(key, window_ms, limit)
      when is_binary(key) and byte_size(key) > 0 and is_integer(window_ms) and window_ms > 0 and is_integer(limit) and
             limit > 0 do
    if enabled?() do
      case backend().hit(key, window_ms, limit) do
        {:allow, _count} -> :ok
        {:deny, _retry_after_ms} -> {:error, :rate_limited}
      end
    else
      :ok
    end
  end

  @doc """
  Returns the backend module to use for rate limiting.
  """
  def backend do
    if redis_url(), do: RedisBackend, else: ETSBackend
  end

  @doc """
  Returns the child spec for the rate limiter backend.
  Called from Application.start/2.
  """
  def child_spec_for_backend do
    case redis_url() do
      url when is_binary(url) -> {RedisBackend, url: url}
      nil -> {ETSBackend, clean_period: to_timeout(minute: 10)}
    end
  end

  # The single source of truth for both readers above. `config/runtime.exs` is the
  # only place that touches REDIS_URL, so there is no second normalization to
  # disagree with — and because presence alone selects the backend, there is no
  # "Redis configured without a URL" state to detect or paper over.
  defp redis_url, do: Application.get_env(:storyarn, :rate_limiter_redis_url)

  defp enabled? do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
