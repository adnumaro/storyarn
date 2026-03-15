defmodule Storyarn.Scenes.ExplorationSessionCrud do
  @moduledoc """
  CRUD operations for exploration sessions.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Scenes.ExplorationSession
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Gets an existing exploration session for a user and project.
  """
  def get_session(user_id, project_id) do
    case Repo.get_by(ExplorationSession, user_id: user_id, project_id: project_id) do
      nil -> nil
      session -> Repo.preload(session, :scene)
    end
  end

  @replace_fields [
    :scene_id,
    :variable_values,
    :collected_ids,
    :player_positions,
    :camera_state,
    :updated_at
  ]

  @doc """
  Upserts an exploration session. Creates if none exists, updates if one does.
  """
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

  @doc """
  Deletes an exploration session (new game).
  """
  def delete_session(user_id, project_id) do
    case Repo.get_by(ExplorationSession, user_id: user_id, project_id: project_id) do
      nil -> {:ok, nil}
      session -> Repo.delete(session)
    end
  end

  @doc """
  Deletes exploration sessions older than the given number of days.
  """
  def cleanup_old_sessions(days \\ 30) do
    cutoff = DateTime.add(TimeHelpers.now(), -days * 86_400, :second)

    from(s in ExplorationSession, where: s.updated_at < ^cutoff)
    |> Repo.delete_all()
  end
end
