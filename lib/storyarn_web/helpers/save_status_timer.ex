defmodule StoryarnWeb.Helpers.SaveStatusTimer do
  @moduledoc "Schedules a delayed reset of the save status indicator for LiveViews."

  @doc """
  Schedules a `:reset_save_status` message after `timeout_ms` milliseconds.
  Returns the socket unchanged (for piping).
  """
  def schedule_reset(socket, timeout_ms \\ 4000) do
    Process.send_after(self(), :reset_save_status, timeout_ms)
    socket
  end
end
