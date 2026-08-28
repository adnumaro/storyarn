defmodule Storyarn.AI.Settlement.Unavailable do
  @moduledoc false
  @behaviour Storyarn.AI.SettlementAdapter

  @impl true
  def available?(_lane), do: false

  @impl true
  def preflight_status(_lane, _workspace_id, _units), do: {:error, :allowance_unavailable}

  @impl true
  def reserve(_operation), do: {:error, :allowance_unavailable}

  @impl true
  def commit(_operation), do: {:error, :allowance_unavailable}

  @impl true
  def release(_operation), do: {:error, :allowance_unavailable}
end
