defmodule Storyarn.Ideation.Sessions.Queries.RoundContext do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.Get
  alias Storyarn.Ideation.Sessions.Queries.Page
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  defguardp valid_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807

  def run(scope, project_id, session_id, opts) do
    with {:ok, session} <- Get.run(scope, project_id, session_id),
         {:ok, limit, through_id, round_ids, selected_id} <- options(opts) do
      {history, next} = pages(session.id, limit, through_id, nil, [])
      active = active_round(session.id, history, next)
      loaded = history ++ List.wrap(active)
      referenced = referenced_rounds(session.id, round_ids ++ List.wrap(selected_id), loaded)
      rounds = Enum.uniq_by(loaded ++ referenced, & &1.id)

      if is_nil(selected_id) or Enum.any?(rounds, &(&1.id == selected_id)) do
        {:ok, %{rounds: rounds, rounds_next: next, active_round: active}}
      else
        {:error, :round_not_found}
      end
    end
  end

  defp options(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, limit, _} <- Page.options(Keyword.take(opts, [:limit])),
         through_id = Keyword.get(opts, :through_id),
         true <- is_nil(through_id) or valid_id(through_id),
         selected_id = Keyword.get(opts, :selected_id),
         true <- is_nil(selected_id) or valid_id(selected_id),
         round_ids = Keyword.get(opts, :round_ids, []),
         true <- is_list(round_ids) and Enum.all?(round_ids, fn id -> valid_id(id) end) do
      {:ok, limit, through_id, Enum.uniq(round_ids), selected_id}
    else
      _ -> {:error, :invalid_options}
    end
  end

  defp options(_opts), do: {:error, :invalid_options}

  defp pages(session_id, limit, through_id, before_id, accumulated) do
    query =
      from(r in Round, where: r.session_id == ^session_id, order_by: [desc: r.id], limit: ^limit)

    query = if before_id, do: where(query, [r], r.id < ^before_id), else: query
    page = Repo.all(query)
    next = if length(page) == limit, do: List.last(page).id
    accumulated = [page | accumulated]

    if through_id && next && next >= through_id,
      do: pages(session_id, limit, through_id, next, accumulated),
      else: {accumulated |> Enum.reverse() |> List.flatten(), next}
  end

  defp active_round(session_id, history, next) do
    case Enum.find(history, &(&1.status == :active)) do
      nil when not is_nil(next) ->
        Repo.one(from(r in Round, where: r.session_id == ^session_id and r.status == :active))

      active ->
        active
    end
  end

  defp referenced_rounds(session_id, round_ids, loaded) do
    loaded = MapSet.new(loaded, & &1.id)

    round_ids
    |> Enum.reject(&MapSet.member?(loaded, &1))
    |> Enum.uniq()
    |> Enum.chunk_every(200)
    |> Enum.flat_map(fn ids ->
      Repo.all(
        from(r in Round,
          where: r.session_id == ^session_id and r.id in ^ids,
          order_by: [desc: r.id]
        )
      )
    end)
  end
end
