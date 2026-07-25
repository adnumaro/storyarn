defmodule StoryarnTest.AI.FakeSettlement do
  @moduledoc false
  @behaviour Storyarn.AI.SettlementAdapter

  @impl true
  def available?(:managed), do: true
  def available?(_lane), do: false

  @impl true
  def preflight_status(:managed, _workspace_id, _units), do: configured_result(:preflight_status)
  def preflight_status(_lane, _workspace_id, _units), do: {:error, :allowance_unavailable}

  @impl true
  def reserve(_operation), do: :ok

  @impl true
  def commit(_operation), do: configured_result(:commit)

  @impl true
  def release(_operation), do: configured_result(:release)

  defp configured_result(action) do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(action, :ok)
  end
end
