defmodule Storyarn.Projects.Access.RateLimits do
  @moduledoc "Project invitation rate-limit policy."

  alias Storyarn.Platform.RateLimiter

  @limit 10
  @window_ms 3_600_000

  def check(project_id, user_id, limit \\ @limit),
    do: RateLimiter.check("invitation:project:#{project_id}:#{user_id}", @window_ms, limit)
end
