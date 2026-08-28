defmodule Storyarn.AI.Integrations.RateLimits do
  @moduledoc "Integration-owned provider validation rate-limit policy."

  alias Storyarn.Platform.RateLimiter

  @limit 3
  @window_ms 60_000

  def check_connect(user_id) when is_integer(user_id) and user_id > 0,
    do: RateLimiter.check("ai_integration_connect:#{user_id}", @window_ms, @limit)
end
