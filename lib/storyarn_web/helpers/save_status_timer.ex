defmodule StoryarnWeb.Helpers.SaveStatusTimer do
  @moduledoc "Schedules a delayed reset of the save status indicator for LiveViews."

  @doc """
  Schedules a tokenized reset message after `timeout_ms` milliseconds.

  The token is stored on the socket so an older timer cannot clear a newer save.
  """
  def schedule_reset(socket, timeout_ms \\ 4000) do
    token = make_ref()
    Process.send_after(self(), {:reset_save_status, token}, timeout_ms)
    Phoenix.Component.assign(socket, :save_status_reset_token, token)
  end

  @doc """
  Marks the save status as :saved and schedules the automatic reset.
  Convenience function that combines assign + schedule_reset.
  """
  def mark_saved(socket) do
    socket
    |> Phoenix.Component.assign(:save_status, :saved)
    |> Phoenix.LiveView.push_event("save_status", %{status: "saved"})
    |> schedule_reset()
  end
end
