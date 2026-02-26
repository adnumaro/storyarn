defmodule Storyarn.RateLimiter do
  @moduledoc """
  Rate limiting service using Hammer v7.

  Uses ETS backend by default and Redis backend in production when
  REDIS_URL is configured (for multi-node support).

  ## Rate Limits

  - Login attempts: 5 per minute per IP
  - Magic link requests: 3 per minute per email
  - Registration: 3 per minute per IP
  - Invitations: 10 per hour per user (configured in invitation modules)

  ## Configuration

  Rate limiting can be disabled for testing:

      config :storyarn, Storyarn.RateLimiter, enabled: false

  Backend selection (set in runtime.exs for prod):

      config :storyarn, :rate_limiter_backend, :redis

  ## Usage

      case RateLimiter.check_login(ip_address) do
        :ok -> attempt_login(...)
        {:error, :rate_limited} -> show_error(...)
      end
  """

  # Login: 5 attempts per minute per IP
  @login_limit 5
  @login_window_ms 60_000

  # Magic link: 3 requests per minute per email
  @magic_link_limit 3
  @magic_link_window_ms 60_000

  # Registration: 3 attempts per minute per IP
  @registration_limit 3
  @registration_window_ms 60_000

  @doc """
  Checks if a login attempt is allowed for the given IP address.

  Returns `:ok` if allowed, `{:error, :rate_limited}` if blocked.
  """
  @spec check_login(String.t()) :: :ok | {:error, :rate_limited}
  def check_login(ip_address) do
    check_rate("login:#{ip_address}", @login_window_ms, @login_limit)
  end

  @doc """
  Checks if a magic link request is allowed for the given email.

  Returns `:ok` if allowed, `{:error, :rate_limited}` if blocked.
  """
  @spec check_magic_link(String.t()) :: :ok | {:error, :rate_limited}
  def check_magic_link(email) do
    normalized_email = String.downcase(email)
    check_rate("magic_link:#{normalized_email}", @magic_link_window_ms, @magic_link_limit)
  end

  @doc """
  Checks if a registration attempt is allowed for the given IP address.

  Returns `:ok` if allowed, `{:error, :rate_limited}` if blocked.
  """
  @spec check_registration(String.t()) :: :ok | {:error, :rate_limited}
  def check_registration(ip_address) do
    check_rate("registration:#{ip_address}", @registration_window_ms, @registration_limit)
  end

  @doc """
  Checks if an invitation is allowed for the given context.

  Used by workspace and project invitation modules.
  Returns `:ok` if allowed, `{:error, :rate_limited}` if blocked.
  """
  @spec check_invitation(String.t(), integer(), integer(), integer()) ::
          :ok | {:error, :rate_limited}
  def check_invitation(context, context_id, user_id, limit \\ 10) do
    # 1 hour window
    window_ms = 60_000 * 60
    check_rate("invitation:#{context}:#{context_id}:#{user_id}", window_ms, limit)
  end

  @doc """
  Returns the backend module to use for rate limiting.
  """
  def backend do
    case Application.get_env(:storyarn, :rate_limiter_backend) do
      :redis -> Storyarn.RateLimiter.RedisBackend
      _ -> Storyarn.RateLimiter.ETSBackend
    end
  end

  @doc """
  Returns the child spec for the rate limiter backend.
  Called from Application.start/2.
  """
  def child_spec_for_backend do
    case Application.get_env(:storyarn, :rate_limiter_backend) do
      :redis ->
        redis_url = System.get_env("REDIS_URL") || "redis://localhost:6379"
        {Storyarn.RateLimiter.RedisBackend, url: redis_url}

      _ ->
        {Storyarn.RateLimiter.ETSBackend, clean_period: :timer.minutes(10)}
    end
  end

  # Private

  defp check_rate(key, window_ms, limit) do
    if enabled?() do
      case backend().hit(key, window_ms, limit) do
        {:allow, _count} -> :ok
        {:deny, _retry_after_ms} -> {:error, :rate_limited}
      end
    else
      :ok
    end
  end

  defp enabled? do
    Application.get_env(:storyarn, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
