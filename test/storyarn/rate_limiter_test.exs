defmodule Storyarn.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Storyarn.RateLimiter

  # Rate limiter is disabled in test config. Tests that verify blocking
  # temporarily enable it, then restore the original setting.
  defp with_rate_limiting_enabled(fun) do
    original = Application.get_env(:storyarn, Storyarn.RateLimiter)
    Application.put_env(:storyarn, Storyarn.RateLimiter, enabled: true)

    try do
      fun.()
    after
      Application.put_env(:storyarn, Storyarn.RateLimiter, original || [])
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

  describe "check_magic_link/1" do
    test "blocks requests over the limit when enabled" do
      with_rate_limiting_enabled(fn ->
        email = "test-ml-block-#{System.unique_integer([:positive])}@example.com"

        # 3 allowed
        for _ <- 1..3, do: assert(:ok = RateLimiter.check_magic_link(email))

        # 4th blocked
        assert {:error, :rate_limited} = RateLimiter.check_magic_link(email)
      end)
    end

    test "normalizes email to lowercase when enabled" do
      with_rate_limiting_enabled(fn ->
        base = "test-ml-case-#{System.unique_integer([:positive])}"
        email_lower = "#{base}@example.com"
        email_upper = "#{String.upcase(base)}@EXAMPLE.COM"

        # Both should count against the same bucket
        for _ <- 1..3, do: RateLimiter.check_magic_link(email_lower)

        assert {:error, :rate_limited} = RateLimiter.check_magic_link(email_upper)
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
      assert RateLimiter.backend() == Storyarn.RateLimiter.ETSBackend
    end

    test "returns Redis backend when configured" do
      original = Application.get_env(:storyarn, :rate_limiter_backend)
      Application.put_env(:storyarn, :rate_limiter_backend, :redis)

      try do
        assert RateLimiter.backend() == Storyarn.RateLimiter.RedisBackend
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
      assert module == Storyarn.RateLimiter.ETSBackend
      assert Keyword.has_key?(opts, :clean_period)
    end

    test "returns Redis child spec when configured" do
      original = Application.get_env(:storyarn, :rate_limiter_backend)
      Application.put_env(:storyarn, :rate_limiter_backend, :redis)

      try do
        {module, opts} = RateLimiter.child_spec_for_backend()
        assert module == Storyarn.RateLimiter.RedisBackend
        assert Keyword.has_key?(opts, :url)
      after
        if original,
          do: Application.put_env(:storyarn, :rate_limiter_backend, original),
          else: Application.delete_env(:storyarn, :rate_limiter_backend)
      end
    end
  end
end
