defmodule Storyarn.Workspaces.Invitations.RateLimits do
  @moduledoc "Workspace invitation rate-limit policy."

  alias Storyarn.Platform.RateLimiter

  @limit 10
  @window_ms 3_600_000

  def check(workspace_id, user_id, limit \\ @limit),
    do: RateLimiter.check("invitation:workspace:#{workspace_id}:#{user_id}", @window_ms, limit)
end
