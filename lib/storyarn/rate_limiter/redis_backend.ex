defmodule Storyarn.RateLimiter.RedisBackend do
  @moduledoc false
  use Hammer, backend: Hammer.Redis
end
