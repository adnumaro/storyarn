defmodule Storyarn.Ideation.Ideas.Commands.Connect do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]

  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Repo

  # Setting membership is idempotent. It cannot overwrite another move or link.
  def run(scope, project_id, session_id, source_id, target_id, connected?)
      when is_boolean(connected?) and source_id != target_id do
    Transaction.run(scope, project_id, session_id, &connect_locked(&1, source_id, target_id, connected?))
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_canvas}

  defp connect_locked(access, source_id, target_id, connected?) do
    with {:ok, _} <- Visible.get(access.session_id, source_id, access.user_id),
         {:ok, _} <- Visible.get(access.session_id, target_id, access.user_id) do
      idea = Repo.get!(Idea, source_id)
      previous = Map.get(idea.canvas, "links", [])
      links = if connected?, do: Enum.uniq(previous ++ [target_id]), else: List.delete(previous, target_id)

      cond do
        links == previous ->
          Transaction.success(%{id: source_id})

        length(links) > 100 ->
          {:error, :invalid_canvas}

        true ->
          persist(idea, links)
      end
    end
  end

  defp persist(idea, links) do
    canvas = idea.canvas |> Map.put("links", links) |> Map.update("version", 1, &(&1 + 1)) |> Map.delete("request_key")
    idea |> change(canvas: canvas) |> Repo.update!()
    audiences = if idea.published_revision, do: [:shared, idea.author_id], else: [idea.author_id]
    Transaction.success(%{id: idea.id}, Enum.reject(audiences, &is_nil/1))
  end
end
