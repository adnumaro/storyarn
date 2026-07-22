defmodule Storyarn.AI.Settlement do
  @moduledoc false

  def available?(lane), do: adapter().available?(lane)
  def reserve(operation), do: adapter().reserve(operation)
  def commit(operation), do: adapter().commit(operation)
  def release(operation), do: adapter().release(operation)

  defp adapter do
    Application.get_env(:storyarn, __MODULE__, Storyarn.AI.Settlement.Unavailable)
  end
end
