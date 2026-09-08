defmodule Storyarn.Ideation.Ideas.Commands.Delete do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1, valid_revision: 1]

  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(scope, project_id, session_id, idea_id, revision) when valid_id(idea_id) and valid_revision(revision) do
    Transaction.run(scope, project_id, session_id, fn access ->
      case Repo.get_by(Idea, id: idea_id, session_id: session_id) do
        nil -> {:error, :not_found}
        idea -> delete(idea, access, revision)
      end
    end)
  end

  def run(_, _, _, _, _), do: {:error, :invalid_parameters}

  defp delete(idea, access, revision) do
    cond do
      not Policy.author?(idea, access.user_id) ->
        {:error, :not_found}

      idea.revision != revision ->
        {:error, :stale_revision}

      idea.deleted_at != nil ->
        Transaction.success(%{id: idea.id, revision: idea.revision, deleted_at: idea.deleted_at})

      true ->
        deleted = idea |> change(deleted_at: %{TimeHelpers.now() | microsecond: {0, 6}}) |> Repo.update!()

        audiences = if deleted.published_revision, do: [:shared, access.user_id], else: [access.user_id]
        Transaction.success(%{id: deleted.id, revision: deleted.revision, deleted_at: deleted.deleted_at}, audiences)
    end
  end
end
