defmodule Storyarn.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Storyarn.RateLimiter
  # Rate limiter is disabled in test config. Tests that verify blocking
  # temporarily enable it, then restore the original setting.
  alias Storyarn.RateLimiter.ETSBackend
  alias Storyarn.RateLimiter.RedisBackend

  defp with_rate_limiting_enabled(fun) do
    original = Application.get_env(:storyarn, RateLimiter)
    Application.put_env(:storyarn, RateLimiter, enabled: true)

    try do
      fun.()
    after
      Application.put_env(:storyarn, RateLimiter, original || [])
    end
  end

  describe "check_login/1" do
    test "allows requests when rate limiting is disabled (test default)" do
      ip = "test-login-#{System.unique_integer([:positive])}"

      # Should always allow when disabled
      for _ <- 1..20, do: assert(:ok = RateLimiter.check_login(ip))
    end

    test "blocks requests over the limit when enabled" do
      with_rate_limiting_enabled(fn ->
        ip = "test-login-block-#{System.unique_integer([:positive])}"

        # 5 allowed
        for _ <- 1..5, do: assert(:ok = RateLimiter.check_login(ip))

        # 6th should be blocked
        assert {:error, :rate_limited} = RateLimiter.check_login(ip)
      end)
    end
  end

  describe "check_sudo/2" do
    test "uses a bucket separate from login and from other users" do
      with_rate_limiting_enabled(fn ->
        ip = "test-sudo-#{System.unique_integer([:positive])}"
        user_id = System.unique_integer([:positive])
        other_user_id = System.unique_integer([:positive])

        for _ <- 1..5, do: assert(:ok = RateLimiter.check_sudo(user_id, ip))

        assert {:error, :rate_limited} = RateLimiter.check_sudo(user_id, ip)
        assert :ok = RateLimiter.check_sudo(other_user_id, ip)
        assert :ok = RateLimiter.check_login(ip)
      end)
    end
  end

  describe "check_registration/1" do
    test "blocks requests over the limit when enabled" do
      with_rate_limiting_enabled(fn ->
        ip = "test-reg-block-#{System.unique_integer([:positive])}"

        for _ <- 1..3, do: assert(:ok = RateLimiter.check_registration(ip))

        assert {:error, :rate_limited} = RateLimiter.check_registration(ip)
      end)
    end
  end

  describe "check_password_reset/2" do
    test "blocks requests over the IP limit when enabled" do
      with_rate_limiting_enabled(fn ->
        ip = "test-password-reset-ip-#{System.unique_integer([:positive])}"

        for index <- 1..3 do
          assert :ok = RateLimiter.check_password_reset(ip, "user#{index}@example.com")
        end

        assert {:error, :rate_limited} =
                 RateLimiter.check_password_reset(ip, "another-user@example.com")
      end)
    end

    test "blocks requests over the normalized email limit when enabled" do
      with_rate_limiting_enabled(fn ->
        email = "Victim#{System.unique_integer([:positive])}@Example.com"

        for index <- 1..3 do
          assert :ok = RateLimiter.check_password_reset("192.0.2.#{index}", email)
        end

        assert {:error, :rate_limited} =
                 RateLimiter.check_password_reset("192.0.2.99", String.downcase(email))
      end)
    end
  end

  describe "check_invitation/3" do
    test "blocks requests over custom limit when enabled" do
      with_rate_limiting_enabled(fn ->
        user_id = System.unique_integer([:positive])
        ctx_id = System.unique_integer([:positive])

        for _ <- 1..2,
            do: assert(:ok = RateLimiter.check_invitation("project", ctx_id, user_id, 2))

        assert {:error, :rate_limited} =
                 RateLimiter.check_invitation("project", ctx_id, user_id, 2)
      end)
    end
  end

  describe "backend/0" do
    test "defaults to ETS backend" do
      assert RateLimiter.backend() == ETSBackend
    end

    test "returns Redis backend when configured" do
      original = Application.get_env(:storyarn, :rate_limiter_backend)
      Application.put_env(:storyarn, :rate_limiter_backend, :redis)

      try do
        assert RateLimiter.backend() == RedisBackend
      after
        if original,
          do: Application.put_env(:storyarn, :rate_limiter_backend, original),
          else: Application.delete_env(:storyarn, :rate_limiter_backend)
      end
    end
  end

  describe "child_spec_for_backend/0" do
    test "returns ETS child spec by default" do
      {module, opts} = RateLimiter.child_spec_for_backend()
      assert module == ETSBackend
      assert Keyword.has_key?(opts, :clean_period)
    end

    test "returns Redis child spec when configured" do
      original = Application.get_env(:storyarn, :rate_limiter_backend)
      Application.put_env(:storyarn, :rate_limiter_backend, :redis)

      try do
        {module, opts} = RateLimiter.child_spec_for_backend()
        assert module == RedisBackend
        assert Keyword.has_key?(opts, :url)
      after
        if original,
          do: Application.put_env(:storyarn, :rate_limiter_backend, original),
          else: Application.delete_env(:storyarn, :rate_limiter_backend)
      end
    end
  end
end
