defmodule Storyarn.Ideation.Sessions.Queries.RoundContext do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.Get
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  # A canvas laid out in bands needs every round to place its headers, so the
  # context is the whole ordered list. Sessions never approach the ceiling.
  @max_rounds 500

  def run(scope, project_id, session_id, opts \\ []) do
    with {:ok, session} <- Get.run(scope, project_id, session_id), do: for_session(session.id, opts)
  end

  # Internal read composition: callers authorize the session before entering.
  def for_session(session_id, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      rounds =
        Repo.all(
          from r in Round,
            where: r.session_id == ^session_id,
            order_by: [asc: r.number],
            limit: @max_rounds
        )

      {:ok, %{rounds: rounds, active_round: Enum.find(rounds, &(&1.status == :active))}}
    else
      {:error, :invalid_options}
    end
  end

  def for_session(_session_id, _opts), do: {:error, :invalid_options}
end
