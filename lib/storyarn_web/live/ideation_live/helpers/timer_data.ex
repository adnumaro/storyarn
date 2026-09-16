defmodule StoryarnWeb.IdeationLive.Helpers.TimerData do
  @moduledoc false
  alias Storyarn.Platform.Shared.TimeHelpers

  def project(nil), do: nil

  def project(timer) do
    timer
    |> Map.take([
      :id,
      :round_id,
      :version,
      :status,
      :deadline_at,
      :remaining_seconds,
      :duration_seconds,
      :close_contributions_on_expiry
    ])
    |> Map.put(:outcome, timer.expiry_outcome)
    |> Map.put(:server_now, TimeHelpers.now())
  end
end
