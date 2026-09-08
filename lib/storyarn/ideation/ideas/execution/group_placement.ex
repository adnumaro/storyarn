defmodule Storyarn.Ideation.Ideas.Execution.GroupPlacement do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.GroupSources
  alias Storyarn.Ideation.Ideas.Rules.Canvas
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  # Groups owns the outer transaction and already holds the shared session lock.
  # Ideas retains ordinary write authority over its geometries.
  def move(access, ids, versions, dx, dy) do
    if Repo.in_transaction?() do
      sources = GroupSources.list(access.session_id, ids)

      with :ok <- validate_versions(sources, versions),
           {:ok, placements} <- placements(sources, dx, dy) do
        now = %{TimeHelpers.now() | microsecond: {0, 6}}
        Enum.each(placements, &persist_placement(&1, now))

        :ok
      end
    else
      {:error, :contribution_transaction_required}
    end
  end

  # Only geometry changes. Merging in SQL avoids loading and decrypting every
  # member's text for a placement-only write; the last single-note receipt is
  # superseded by the group movement.
  defp persist_placement({id, canvas}, now) do
    {1, _} =
      Repo.update_all(
        from(i in Idea,
          where: i.id == ^id,
          update: [
            set: [canvas: fragment("(? || ?) - 'request_key'", i.canvas, type(^canvas, :map)), updated_at: ^now]
          ]
        ),
        []
      )
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
        {:ok, canvas} ->
          version = Map.get(source.canvas, "version", 0) + 1
          {:cont, {:ok, [{source.idea_id, Map.put(canvas, "version", version)} | result]}}

        error ->
          {:halt, error}
      end
    end)
  end
end
