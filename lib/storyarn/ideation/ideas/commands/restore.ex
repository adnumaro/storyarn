defmodule Storyarn.Ideation.Ideas.Commands.Restore do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1, valid_revision: 1]

  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Execution.Revisions
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Repo

  def run(scope, project_id, session_id, idea_id, revision, deleted_at)
      when valid_id(idea_id) and valid_revision(revision) do
    with {:ok, marker} <- marker(deleted_at) do
      Transaction.run(scope, project_id, session_id, &restore_locked(&1, idea_id, revision, marker))
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_parameters}

  defp restore_locked(access, idea_id, revision, marker) do
    case Repo.get_by(Idea, id: idea_id, session_id: access.session_id) do
      nil -> {:error, :not_found}
      idea -> restore(idea, access, revision, marker)
    end
  end

  defp marker(%DateTime{} = value), do: {:ok, value}

  defp marker(value) when is_binary(value) and byte_size(value) <= 40 do
    case DateTime.from_iso8601(value) do
      {:ok, value, _offset} -> {:ok, value}
      _ -> {:error, :invalid_parameters}
    end
  end

  defp marker(_), do: {:error, :invalid_parameters}

  defp restore(idea, access, revision, marker) do
    cond do
      not Policy.author?(idea, access.user_id) ->
        {:error, :not_found}

      is_nil(idea.deleted_at) and idea.revision == revision + 1 ->
        # An uncertain undo can be replayed while its restored head is unchanged.
        # Later edits or another delete/restore cycle cannot match this revision.
        result(idea, access, [])

      idea.revision != revision ->
        {:error, :stale_revision}

      is_nil(idea.deleted_at) or DateTime.compare(idea.deleted_at, marker) != :eq ->
        {:error, :stale_deletion}

      true ->
        content = Repo.get_by!(Revision, idea_id: idea.id, number: idea.revision)
        restored = idea |> change(deleted_at: nil, revision: revision + 1) |> Repo.update!()
        Revisions.insert(restored, content, access.user_id)

        restored =
          if access.configuration.private_mode,
            do: restored,
            else: Publication.publish_creation(restored, access.user_id)

        result(restored, access, audiences(restored, access.user_id))
    end
  end

  defp audiences(%{published_revision: nil}, actor_id), do: [actor_id]
  defp audiences(_idea, actor_id), do: [:shared, :comment_sources, actor_id]

  defp result(idea, access, audiences) do
    with {:ok, view} <- Visible.get(idea.session_id, idea.id, access.user_id) do
      Transaction.success(view, audiences)
    end
  end
end
