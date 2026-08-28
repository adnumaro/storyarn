defmodule Storyarn.AI.SettlementAdapter do
  @moduledoc "Configurable settlement contract implemented by the managed-spend capability."

  alias Storyarn.AI.Operation

  @callback available?(lane :: atom()) :: boolean()
  @callback preflight_status(lane :: atom(), workspace_id :: pos_integer(), units :: pos_integer()) ::
              :ok | {:error, atom()}
  @callback reserve(Operation.t()) :: :ok | {:error, atom()}
  @callback commit(Operation.t()) :: :ok | {:error, atom()}
  @callback release(Operation.t()) :: :ok | {:error, atom()}
end
