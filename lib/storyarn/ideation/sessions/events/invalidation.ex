defmodule Storyarn.Ideation.Sessions.Events.Invalidation do
  @moduledoc false
  alias Phoenix.PubSub
  alias Storyarn.Repo

  def subscribe(project_id), do: PubSub.subscribe(Storyarn.PubSub, topic(project_id))

  # Nested callers still own their commit. Never announce an uncommitted change;
  # the board's authorized reconciliation also covers those callers.
  def notify(result, project_id, change \\ :board)

  def notify({:ok, _} = result, project_id, change) do
    if !Repo.in_transaction?() do
      PubSub.broadcast(Storyarn.PubSub, topic(project_id), {:ideation_sessions_changed, project_id})
      notify_comments(project_id, change)
    end

    result
  end

  def notify(result, _project_id, _change), do: result

  # The session tree shows per-session facts (parked notes) that change through
  # idea writes. Those writers announce after their own commit.
  def broadcast_tree(project_id) do
    if !Repo.in_transaction?(),
      do: PubSub.broadcast(Storyarn.PubSub, topic(project_id), {:ideation_sessions_changed, project_id})

    :ok
  end

  # Only compare persisted source facts captured under the session lock. Timer,
  # round, title and no-op mutations must not wake the notification inbox.
  def comment_change(before, after_session) do
    cond do
      before.deleted_at != after_session.deleted_at ->
        :sources

      before.title != after_session.title ->
        :activity

      true ->
        :board
    end
  end

  defp notify_comments(project_id, :sources), do: Storyarn.Projects.invalidate_ideation_comment_sources(project_id)

  defp notify_comments(project_id, :activity), do: Storyarn.Projects.invalidate_ideation_comment_activity(project_id)

  defp notify_comments(_project_id, :board), do: :ok
  defp topic(project_id), do: "ideation:#{project_id}:sessions"
end
