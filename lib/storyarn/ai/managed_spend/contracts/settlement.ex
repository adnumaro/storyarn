defmodule Storyarn.AI.Settlement do
  @moduledoc false

  alias Storyarn.AI.Operation

  @spec available?(atom()) :: boolean()
  def available?(lane), do: adapter().available?(lane)

  @spec preflight_status(atom(), pos_integer(), pos_integer()) :: :ok | {:error, atom()}
  def preflight_status(lane, workspace_id, units), do: adapter().preflight_status(lane, workspace_id, units)

  @spec reserve(Operation.t()) :: :ok | {:error, atom()}
  def reserve(operation), do: adapter().reserve(operation)

  @spec commit(Operation.t()) :: :ok | {:error, atom()}
  def commit(operation), do: adapter().commit(operation)

  @spec release(Operation.t()) :: :ok | {:error, atom()}
  def release(operation), do: adapter().release(operation)

  defp adapter do
    Application.get_env(:storyarn, __MODULE__, Storyarn.AI.Settlement.Unavailable)
  end
end
