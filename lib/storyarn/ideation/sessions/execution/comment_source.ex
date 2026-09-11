defmodule Storyarn.Ideation.Sessions.Execution.CommentSource do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.ProjectAccess
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  # Comment writes hold the project authorization lock first, then this session
  # share lock fences private-mode changes until the message transaction commits.
  def get(scope, project_id, session_id, opts) do
    with :ok <- ProjectAccess.authorize(scope, project_id) do
      query = from(s in Session, where: s.project_id == ^project_id and s.id == ^session_id and is_nil(s.deleted_at))
      query = if opts[:lock] == :share, do: lock(query, "FOR SHARE"), else: query

      case Repo.one(query) do
        %Session{} = session ->
          {:ok,
           %{
             id: session.id,
             name: session.title,
             private_mode: session.configuration.private_mode,
             inserted_at: DateTime.truncate(session.inserted_at, :second),
             recovery_identity: session.recovery_identity
           }}

        _ ->
          {:error, :not_found}
      end
    end
  end
end
