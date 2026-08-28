defmodule Storyarn.Flows.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    Supervisor.init(
      [
        Storyarn.Flows.DebugSessionStore,
        Storyarn.Flows.NavigationHistoryStore
      ],
      strategy: :one_for_one
    )
  end
end
