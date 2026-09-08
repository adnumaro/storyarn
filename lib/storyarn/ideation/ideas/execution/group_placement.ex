defmodule Storyarn.Ideation.Ideas.Execution.GroupPlacement do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.GroupSources
  alias Storyarn.Ideation.Ideas.Rules.Canvas
  alias Storyarn.Repo

  # Groups owns the outer transaction and already holds the shared session lock.
  # Ideas retains ordinary write authority over its geometries.
  def move(access, ids, versions, dx, dy) do
    if Repo.in_transaction?() do
      sources = GroupSources.list(access.session_id, ids)

      with :ok <- validate_versions(sources, versions),
           {:ok, placements} <- placements(sources, dx, dy) do
        Enum.each(placements, &persist_placement/1)

        :ok
      end
    else
      {:error, :contribution_transaction_required}
    end
  end

  defp persist_placement({id, canvas}) do
    idea = Repo.get!(Idea, id)

    updated =
      Map.merge(idea.canvas, Map.put(canvas, "version", Map.get(idea.canvas, "version", 0) + 1))

    idea |> change(canvas: Map.delete(updated, "request_key")) |> Repo.update!()
  end

  defp validate_versions(sources, versions) do
    expected = Map.new(sources, &{&1.idea_id, Map.get(&1.canvas, "version", 0)})
    if expected == versions, do: :ok, else: {:error, :stale_canvas}
  end

  defp placements(sources, dx, dy) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, result} ->
      attrs =
        source.canvas
        |> Map.put("x", Map.get(source.canvas, "x", 0) + dx)
        |> Map.put("y", Map.get(source.canvas, "y", 0) + dy)

      case Canvas.normalize(attrs) do
        {:ok, canvas} -> {:cont, {:ok, [{source.idea_id, canvas} | result]}}
        error -> {:halt, error}
      end
    end)
  end
end
