defmodule Storyarn.Platform.EventReaction do
  @moduledoc """
  Contract for a Platform-owned, best-effort reaction to context events.

  Reactions declare the event types they understand. `EventTracker` owns the
  routing table and invokes only the registered reactions for each event.
  Durable work must use a persisted, idempotent workflow instead.
  """

  @type event :: {atom(), atom()}

  @callback events() :: [event()]
  @callback handle(term(), atom(), atom(), map()) :: :ok
end
