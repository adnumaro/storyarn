defmodule StoryarnWeb.Helpers.AutoSnapshot do
  @moduledoc """
  Debounced auto-snapshot scheduling for entity editors.

  The entity_type parameter is accepted for interface consistency but
  auto-versioning gating is handled at the context facade level
  (e.g. `Flows.maybe_create_version/3`) to avoid double-checking.
  """

  import Phoenix.Component, only: [assign: 3]

  @debounce_ms 30_000

  @doc """
  Schedules (or resets) a debounced auto-snapshot timer.

  Accepts an optional entity_type for interface consistency.
  The actual auto-versioning gate lives in each context facade's
  `maybe_create_version/3`, which checks the project setting before persisting.
  """
  def schedule(socket, _entity_type), do: do_schedule(socket)

  @doc """
  Cancels a pending auto-snapshot timer, if any.
  Returns the socket with `:auto_snapshot_ref` cleared.
  """
  def cancel(socket) do
    if timer = socket.assigns[:auto_snapshot_timer] do
      Process.cancel_timer(timer)
    end

    socket
    |> assign(:auto_snapshot_timer, nil)
    |> assign(:auto_snapshot_ref, nil)
  end

  defp do_schedule(socket) do
    if timer = socket.assigns[:auto_snapshot_timer] do
      Process.cancel_timer(timer)
    end

    token = make_ref()
    timer = Process.send_after(self(), {:try_auto_snapshot, token}, @debounce_ms)

    socket
    |> assign(:auto_snapshot_timer, timer)
    |> assign(:auto_snapshot_ref, token)
  end
end
