defmodule Storyarn.Platform.RateLimiter.RedisBackend do
  @moduledoc false

  # Hammer otherwise derives the Redis namespace from __MODULE__. Retaining
  # the pre-Platform value keeps counters continuous across the module move and
  # prevents rolling releases from maintaining two independent limits.
  @namespace_prefix "Storyarn.RateLimiter.RedisBackend"
  use Hammer, backend: Hammer.Redis, prefix: @namespace_prefix

  @doc false
  @spec namespace_prefix() :: String.t()
  def namespace_prefix, do: @namespace_prefix
end
