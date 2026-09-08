defmodule Storyarn.Ideation.Sessions.Events.Invalidation do
  @moduledoc false
  alias Phoenix.PubSub
  alias Storyarn.Repo

  def subscribe(project_id), do: PubSub.subscribe(Storyarn.PubSub, topic(project_id))

  # Nested callers still own their commit. Never announce an uncommitted change;
  # the board's authorized reconciliation also covers those callers.
  def notify({:ok, _} = result, project_id) do
    if !Repo.in_transaction?() do
      PubSub.broadcast(Storyarn.PubSub, topic(project_id), {:ideation_sessions_changed, project_id})
    end

    result
  end

  def notify(result, _project_id), do: result
  defp topic(project_id), do: "ideation:#{project_id}:sessions"
end
