defmodule Storyarn.Ideation.Sessions.Adapters.TimerActor do
  @moduledoc false
  alias Storyarn.Accounts

  def scope(nil), do: {:error, :actor_unavailable}

  def scope(actor_id) do
    {:ok, actor_id |> Accounts.get_user!() |> Accounts.scope_for_user()}
  rescue
    Ecto.NoResultsError -> {:error, :actor_unavailable}
  end
end
