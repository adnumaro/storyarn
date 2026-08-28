defmodule Storyarn.Scenes.Exploration.Queries.Sessions do
  @moduledoc """
  Read side for persisted Scene exploration sessions.

  Session reads belong to exploration and return the stable
  `Storyarn.Scenes.ExplorationSession` entity.
  """

  alias Storyarn.Repo
  alias Storyarn.Scenes.ExplorationSession

  @doc "Gets an existing exploration session for a user and project."
  def get_session(user_id, project_id) do
    case Repo.get_by(ExplorationSession, user_id: user_id, project_id: project_id) do
      nil -> nil
      session -> Repo.preload(session, :scene)
    end
  end
end
