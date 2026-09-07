defmodule Storyarn.Ideation.Ideas.Commands.UpdateCanvas do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]

  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Rules.Canvas
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Repo

  def run(scope, project_id, session_id, idea_id, expected, attrs)
      when is_integer(expected) and expected >= 0 and is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs),
         {:ok, placement} <- Canvas.normalize(attrs) do
      Transaction.run(scope, project_id, session_id, &update_locked(&1, idea_id, expected, key, placement))
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_canvas}

  defp update_locked(access, idea_id, expected, key, placement) do
    with {:ok, _} <- Visible.get(access.session_id, idea_id, access.user_id) do
      # The contribution lock serializes archive, recovery and canvas writes.
      idea = Repo.get!(Idea, idea_id)
      current = idea.canvas

      cond do
        current["request_key"] == key and Map.take(current, ~w(x y width color)) == placement ->
          Transaction.success(projection(idea, access.user_id))

        current["request_key"] == key ->
          {:error, :idempotency_conflict}

        Map.get(current, "version", 0) != expected ->
          {:error, :stale_canvas}

        true ->
          persist(idea, placement, expected, key, access.user_id)
      end
    end
  end

  defp persist(idea, placement, expected, key, actor_id) do
    canvas = Map.merge(Map.merge(idea.canvas, placement), %{"version" => expected + 1, "request_key" => key})
    updated = idea |> change(canvas: canvas) |> Repo.update!()
    audiences = if idea.published_revision, do: [:shared, idea.author_id], else: [idea.author_id]
    Transaction.success(projection(updated, actor_id), Enum.reject(audiences, &is_nil/1))
  end

  defp projection(idea, actor_id),
    do: Map.put(Map.delete(idea.canvas, "request_key"), "links", Visible.visible_links(idea, actor_id))
end
