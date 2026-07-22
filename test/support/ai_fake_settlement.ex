defmodule StoryarnTest.AI.FakeSettlement do
  @moduledoc false
  @behaviour Storyarn.AI.SettlementAdapter

  @impl true
  def available?(:managed), do: true
  def available?(_lane), do: false

  @impl true
  def reserve(_operation), do: :ok

  @impl true
  def commit(_operation), do: :ok

  @impl true
  def release(_operation), do: :ok
end
