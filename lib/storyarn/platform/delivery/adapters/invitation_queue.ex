defmodule Storyarn.Platform.Delivery.Adapters.InvitationQueue do
  @moduledoc """
  Oban adapter for already-encrypted invitation delivery requests.

  Invitation ownership and copy remain with the producing context. This
  adapter only translates the transport-neutral request into the stable worker
  identity persisted by Oban.
  """

  alias Storyarn.Workers.DeliverInvitationWorker

  @spec enqueue(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(attrs) when is_map(attrs) do
    attrs
    |> DeliverInvitationWorker.new()
    |> Oban.insert()
  end
end
