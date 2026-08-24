defmodule Storyarn.Platform.RateLimiter.ETSBackend do
  @moduledoc false
  use Hammer, backend: :ets
end
