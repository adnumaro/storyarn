defmodule Storyarn.Accounts.Authentication.RateLimits do
  @moduledoc "Account-owned authentication and registration rate-limit policy."

  alias Storyarn.Platform.RateLimiter

  @login_limit 5
  @login_window_ms 60_000
  @sudo_limit 5
  @sudo_window_ms 60_000
  @registration_limit 3
  @registration_window_ms 60_000
  @password_reset_limit 3
  @password_reset_window_ms 900_000

  def check_login(ip_address), do: RateLimiter.check("login:#{ip_address}", @login_window_ms, @login_limit)

  def check_sudo(user_id, ip_address) when is_integer(user_id) and user_id > 0,
    do: RateLimiter.check("sudo:#{user_id}:#{ip_address}", @sudo_window_ms, @sudo_limit)

  def check_registration(ip_address),
    do: RateLimiter.check("registration:#{ip_address}", @registration_window_ms, @registration_limit)

  def check_password_reset(ip_address, email) do
    normalized_email = normalize_email(email)

    with :ok <-
           RateLimiter.check(
             "password_reset:ip:#{ip_address}",
             @password_reset_window_ms,
             @password_reset_limit
           ) do
      RateLimiter.check(
        "password_reset:email:#{normalized_email}",
        @password_reset_window_ms,
        @password_reset_limit
      )
    end
  end

  defp normalize_email(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  defp normalize_email(_email), do: "missing_email"
end
