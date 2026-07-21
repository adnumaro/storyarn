defmodule StoryarnWeb.Live.Hooks.PaletteAnalytics do
  @moduledoc """
  Tracks command-palette product events for every LiveView in the
  authenticated app session, without per-tool handlers.

  The palette island pushes `palette_opened`, `palette_command_executed`, and
  `palette_search_no_results`; this hook maps them to the allowlisted
  `Storyarn.Analytics` events. Payloads are rebuilt from validated params —
  raw client params never reach the adapter. Malformed events (only our own
  client produces these) fall through like any unknown event.
  """

  alias Storyarn.Analytics

  def on_mount(:track_palette, _params, _session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(
       socket,
       :palette_analytics,
       :handle_event,
       &handle_palette_event/3
     )}
  end

  defp handle_palette_event("palette_opened", %{"surface" => surface}, socket) when is_binary(surface) do
    Analytics.track(socket.assigns.current_scope, "palette opened", %{surface: surface})
    {:halt, socket}
  end

  defp handle_palette_event("palette_command_executed", %{"command_id" => command_id, "surface" => surface}, socket)
       when is_binary(command_id) and is_binary(surface) do
    Analytics.track(socket.assigns.current_scope, "palette command executed", %{
      command_id: command_id,
      surface: surface
    })

    {:halt, socket}
  end

  defp handle_palette_event("palette_search_no_results", %{"query_length" => query_length, "surface" => surface}, socket)
       when is_integer(query_length) and is_binary(surface) do
    Analytics.track(socket.assigns.current_scope, "palette search no results", %{
      query_length: query_length,
      surface: surface
    })

    {:halt, socket}
  end

  defp handle_palette_event(_event, _params, socket), do: {:cont, socket}
end
