defmodule Storyarn.AI.Operations.RateLimits do
  @moduledoc "Operations-owned accepted-execution rate-limit policy."

  alias Storyarn.Platform.RateLimiter

  @default_limit 20
  @window_ms 60_000

  def check_execution(user_id, task_id, limit \\ @default_limit)
      when is_integer(user_id) and user_id > 0 and is_binary(task_id) and is_integer(limit) and limit > 0,
      do: RateLimiter.check("ai_execution:#{user_id}:#{task_id}", @window_ms, limit)
end
