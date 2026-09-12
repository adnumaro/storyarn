defmodule Storyarn.Ideation.Sessions.Events.TimerInvalidation do
  @moduledoc false
  alias Storyarn.Repo

  # A delivery may reach an unavailable database after the original schedule
  # notification was lost. This carries no state; it asks the runtime to retry
  # its durable inventory, even if the individual delivery later exhausts retries.
  def wake do
    if !Repo.in_transaction?(),
      do: Phoenix.PubSub.broadcast(Storyarn.PubSub, "ideation:timers", :ideation_timers_changed)

    :ok
  end

  def notify({:ok, _} = result) do
    wake()
    result
  end

  def notify(result), do: result
end
