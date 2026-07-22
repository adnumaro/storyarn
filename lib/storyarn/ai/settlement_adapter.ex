defmodule Storyarn.AI.SettlementAdapter do
  @moduledoc "Boundary implemented by Slice 3's managed allowance ledger."

  alias Storyarn.AI.Operation

  @callback available?(lane :: atom()) :: boolean()
  @callback reserve(Operation.t()) :: :ok | {:error, atom()}
  @callback commit(Operation.t()) :: :ok | {:error, atom()}
  @callback release(Operation.t()) :: :ok | {:error, atom()}
end
