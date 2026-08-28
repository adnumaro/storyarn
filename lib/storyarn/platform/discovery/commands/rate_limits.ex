defmodule Storyarn.Platform.CommandPalette.RateLimits do
  @moduledoc "Command-palette-owned deep-search rate-limit policy."

  alias Storyarn.Platform.RateLimiter

  @default_limit 12
  @window_ms 10_000

  def check_deep_search(user_id, limit \\ @default_limit)
      when is_integer(user_id) and user_id > 0 and is_integer(limit) and limit > 0,
      do: RateLimiter.check("palette_deep_search:#{user_id}", @window_ms, limit)
end
