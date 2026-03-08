defmodule Storyarn.SentryEventFilter do
  @moduledoc """
  Custom Sentry event filter to suppress noisy errors.

  Extends the default filter with LiveView-specific exclusions
  (client disconnects, navigation events, etc.).
  """

  @behaviour Sentry.EventFilter

  @impl true
  defdelegate exclude_exception?(exception, source), to: Sentry.DefaultEventFilter
end
