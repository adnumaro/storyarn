defmodule Storyarn.Analytics.NoopAdapter do
  @moduledoc false

  def capture(_payload), do: :ok
  def identify(_payload), do: :ok
end
