defmodule Storyarn.Ideation.Sessions.Queries.Rounds do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.Get
  alias Storyarn.Ideation.Sessions.Queries.Page
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  def run(scope, project_id, session_id, opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, session} <- Get.run(scope, project_id, session_id),
         {:ok, limit, before_id} <- Page.options(opts),
         status when status in [:all, :planned, :active, :closed, :cancelled] <- Keyword.get(opts, :status, :all),
         {:ok, ids} <- ids(Keyword.get(opts, :ids, :all)) do
      query = from r in Round, where: r.session_id == ^session.id, order_by: [desc: r.id], limit: ^limit
      query = if status == :all, do: query, else: where(query, [r], r.status == ^status)
      query = if ids == :all, do: query, else: where(query, [r], r.id in ^ids)
      query = if before_id, do: where(query, [r], r.id < ^before_id), else: query
      {:ok, Repo.all(query)}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_options}
    end
  end

  def run(_scope, _project_id, _session_id, _opts), do: {:error, :invalid_options}

  # The Ideas reader has already authorized the session before using this port.
  def validate_filter(_session_id, filter) when filter in [:all, nil], do: {:ok, filter}

  def validate_filter(session_id, round_id)
      when is_integer(round_id) and round_id > 0 and round_id <= 9_223_372_036_854_775_807 do
    if Repo.exists?(from r in Round, where: r.session_id == ^session_id and r.id == ^round_id),
      do: {:ok, round_id},
      else: {:error, :round_not_found}
  end

  def validate_filter(_session_id, _round_id), do: {:error, :invalid_options}

  defp ids(:all), do: {:ok, :all}

  defp ids(ids) when is_list(ids) and length(ids) <= 200 do
    if Enum.all?(ids, &(is_integer(&1) and &1 > 0 and &1 <= 9_223_372_036_854_775_807)),
      do: {:ok, ids},
      else: {:error, :invalid_options}
  end

  defp ids(_ids), do: {:error, :invalid_options}
end
