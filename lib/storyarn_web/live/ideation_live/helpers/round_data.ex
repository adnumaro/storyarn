defmodule StoryarnWeb.IdeationLive.Helpers.RoundData do
  @moduledoc false
  alias Storyarn.Ideation

  @page_size 50

  def load(scope, project_id, session_id, through, ideas, selected) do
    references = Enum.map(ideas, & &1.round_id) ++ List.wrap(if(is_integer(selected), do: selected))

    with {:ok, rounds, next} <- pages(scope, project_id, session_id, through, nil, []),
         {:ok, active} <- Ideation.list_rounds(scope, project_id, session_id, status: :active, limit: 1),
         {:ok, referenced} <- referenced_rounds(scope, project_id, session_id, references, rounds ++ active) do
      {:ok,
       %{
         rounds: Enum.map(Enum.uniq_by(rounds ++ active ++ referenced, & &1.id), &round_view/1),
         rounds_next: next,
         active_round: if(active != [], do: round_view(hd(active)))
       }}
    end
  end

  def validate_filter(_scope, _project_id, _session_id, filter) when filter in [:all, nil], do: :ok

  def validate_filter(scope, project_id, session_id, id) do
    case Ideation.list_rounds(scope, project_id, session_id, ids: [id], limit: 1) do
      {:ok, [_]} -> :ok
      {:ok, []} -> {:error, :round_not_found}
      error -> error
    end
  end

  defp pages(scope, project_id, session_id, through, before_id, accumulated) do
    with {:ok, page} <- Ideation.list_rounds(scope, project_id, session_id, before_id: before_id, limit: @page_size) do
      next = if length(page) == @page_size, do: List.last(page).id
      rounds = accumulated ++ page

      if through && next && next >= through,
        do: pages(scope, project_id, session_id, through, next, rounds),
        else: {:ok, rounds, next}
    end
  end

  # A selected round or a visible note's original round may be older than the
  # browser's loaded page. Keep its context even when it has no visible notes.
  defp referenced_rounds(scope, project_id, session_id, references, loaded) do
    loaded = MapSet.new(loaded, & &1.id)

    references
    |> Enum.reject(&(is_nil(&1) or MapSet.member?(loaded, &1)))
    |> Enum.uniq()
    |> Enum.chunk_every(200)
    |> Enum.reduce_while({:ok, []}, fn ids, {:ok, accumulated} ->
      case Ideation.list_rounds(scope, project_id, session_id, ids: ids, limit: 200) do
        {:ok, rounds} -> {:cont, {:ok, accumulated ++ rounds}}
        error -> {:halt, error}
      end
    end)
  end

  defp round_view(value),
    do: Map.take(value, [:id, :session_id, :number, :prompt, :status, :started_at, :closed_at, :inserted_at, :updated_at])
end
