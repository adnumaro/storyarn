defmodule Storyarn.RateLimiter.ETSBackend do
  @moduledoc false
  use Hammer, backend: :ets
end
