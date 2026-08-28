defmodule Storyarn.Scenes.Exploration.Commands.Sessions do
  @moduledoc """
  Write side for persisted Scene exploration sessions.

  It deliberately preserves the former upsert, delete, and cleanup semantics;
  only ownership and placement change.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.ExplorationSession

  @replace_fields [
    :scene_id,
    :variable_values,
    :collected_ids,
    :player_positions,
    :camera_state,
    :updated_at
  ]

  @doc "Upserts an exploration session. Creates if none exists, updates if one does."
  def save_session(user_id, project_id, attrs) do
    attrs =
      Map.merge(attrs, %{
        user_id: user_id,
        project_id: project_id
      })

    %ExplorationSession{}
    |> ExplorationSession.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, @replace_fields},
      conflict_target: [:user_id, :project_id],
      returning: true
    )
  end

  @doc "Deletes an exploration session (new game)."
  def delete_session(user_id, project_id) do
    Repo.delete_all(
      from(session in ExplorationSession,
        where: session.user_id == ^user_id and session.project_id == ^project_id
      )
    )

    {:ok, nil}
  end

  @doc "Deletes exploration sessions older than the given number of days."
  def cleanup_old_sessions(days \\ 30) do
    cutoff = DateTime.add(TimeHelpers.now(), -days * 86_400, :second)

    Repo.delete_all(from(session in ExplorationSession, where: session.updated_at < ^cutoff))
  end
end
