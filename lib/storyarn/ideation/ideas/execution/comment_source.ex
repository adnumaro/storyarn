defmodule Storyarn.Ideation.Ideas.Execution.CommentSource do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  # Comments consume identity and audience, never the author's editable revision.
  def get(%{user: %{id: _}} = scope, project_id, session_id, idea_id, opts)
      when is_integer(project_id) and project_id > 0 and is_integer(session_id) and session_id > 0 and
             (is_nil(idea_id) or (is_integer(idea_id) and idea_id > 0)) do
    case Sessions.comment_source(scope, project_id, session_id, opts) do
      {:ok, session} -> source(session, idea_id, opts)
      _ -> {:error, :not_found}
    end
  end

  def get(_, _, _, _, _), do: {:error, :not_found}

  defp source(session, nil, _opts), do: {:ok, session}

  defp source(%{private_mode: true}, _idea_id, _opts), do: {:error, :not_found}

  defp source(session, idea_id, opts) do
    case from(i in Idea,
           where: i.session_id == ^session.id and i.id == ^idea_id and is_nil(i.deleted_at),
           where: not is_nil(i.published_revision)
         )
         |> maybe_lock(opts)
         |> Repo.one() do
      %Idea{} = idea -> {:ok, identity(idea, "Idea ##{idea.id}")}
      _ -> {:error, :not_found}
    end
  end

  defp identity(source, name) do
    %{
      id: source.id,
      inserted_at: DateTime.truncate(source.inserted_at, :second),
      recovery_identity: source.recovery_identity,
      name: name
    }
  end

  defp maybe_lock(query, opts) do
    if opts[:lock] == :share, do: lock(query, "FOR SHARE"), else: query
  end
end
