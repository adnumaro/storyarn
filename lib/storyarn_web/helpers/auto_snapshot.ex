defmodule StoryarnWeb.Helpers.AutoSnapshot do
  @moduledoc "Debounced auto-snapshot scheduling for entity editors."

  import Phoenix.Component, only: [assign: 3]

  @debounce_ms 30_000

  @doc """
  Schedules (or resets) a debounced auto-snapshot timer.
  Stores the timer in `:auto_snapshot_timer` and a unique token in `:auto_snapshot_ref`.
  """
  def schedule(socket) do
    if timer = socket.assigns[:auto_snapshot_timer] do
      Process.cancel_timer(timer)
    end

    token = make_ref()
    timer = Process.send_after(self(), {:try_auto_snapshot, token}, @debounce_ms)

    socket
    |> assign(:auto_snapshot_timer, timer)
    |> assign(:auto_snapshot_ref, token)
  end

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
end
