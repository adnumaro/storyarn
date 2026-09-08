defmodule StoryarnWeb.IdeationLive.Helpers.RoundData do
  @moduledoc false
  alias Storyarn.Ideation

  @page_size 50

  def load(scope, project_id, session_id, through, ideas, selected) do
    opts = [
      through_id: through,
      round_ids: ideas |> Enum.map(& &1.round_id) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      selected_id: if(is_integer(selected), do: selected),
      limit: @page_size
    ]

    with {:ok, context} <- Ideation.get_round_context(scope, project_id, session_id, opts) do
      {:ok,
       %{
         rounds: Enum.map(context.rounds, &round_view/1),
         rounds_next: context.rounds_next,
         active_round: if(context.active_round, do: round_view(context.active_round))
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

  defp round_view(value),
    do: Map.take(value, [:id, :session_id, :number, :prompt, :status, :started_at, :closed_at, :inserted_at, :updated_at])
end
