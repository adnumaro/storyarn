defmodule Storyarn.Platform.Notifications.Adapters.PubSub do
  @moduledoc """
  Phoenix PubSub adapter for notification inbox invalidation signals.

  PostgreSQL remains the source of truth. These messages only tell connected
  recipients to refetch committed state.
  """

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, topic)
  end

  @spec broadcast(String.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub, topic, message)
  end
end
