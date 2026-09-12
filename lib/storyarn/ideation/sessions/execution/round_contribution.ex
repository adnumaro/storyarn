defmodule Storyarn.Ideation.Sessions.Execution.RoundContribution do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  # The Ideas command holds the current session lock for the whole creation.
  def resolve(access, selection) do
    if Repo.in_transaction?(),
      do: select_round(access.session_id, selection),
      else: {:error, :contribution_transaction_required}
  end

  defp select_round(session_id, :active) do
    session_id
    |> active_round()
    |> contribution()
  end

  defp select_round(_session_id, nil), do: contribution(nil)

  defp select_round(session_id, round_id)
       when is_integer(round_id) and round_id > 0 and round_id <= 9_223_372_036_854_775_807 do
    case Repo.one(from r in Round, where: r.session_id == ^session_id and r.id == ^round_id) do
      nil -> {:error, :round_not_found}
      round -> contribution(round)
    end
  end

  defp select_round(_session_id, _round_id), do: {:error, :invalid_round}

  defp active_round(session_id),
    do: Repo.one(from r in Round, where: r.session_id == ^session_id and r.status == :active)

  defp contribution(nil), do: {:ok, %{round_id: nil, late_contribution: false}}
  defp contribution(%{status: :planned}), do: {:error, :round_not_started}
  defp contribution(%{status: :cancelled}), do: {:error, :round_cancelled}

  defp contribution(round), do: {:ok, %{round_id: round.id, late_contribution: round.status == :closed}}
end
