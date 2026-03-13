defmodule StoryarnWeb.Helpers.DraftTouchTimer do
  @moduledoc "Schedules a debounced touch of draft last_edited_at after saves."

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Schedules a `:touch_draft` message after 30 seconds.
  Only schedules if the socket has `is_draft: true`.
  Cancels any previously scheduled timer to avoid redundant touches.
  Returns the socket (for piping).
  """
  def schedule_touch(socket) do
    if socket.assigns[:is_draft] do
      if ref = socket.assigns[:_draft_touch_ref] do
        Process.cancel_timer(ref)
      end

      ref = Process.send_after(self(), :touch_draft, 30_000)
      assign(socket, :_draft_touch_ref, ref)
    else
      socket
    end
  end
end
