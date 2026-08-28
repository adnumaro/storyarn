defmodule Storyarn.Platform.Delivery do
  @moduledoc """
  Public boundary for Platform-owned durable delivery requests.

  Producing contexts retain the semantic intent and content. Platform adapts a
  completed request to the durable delivery mechanism.
  """

  alias Storyarn.Platform.Delivery.Adapters.InvitationQueue

  @doc "Persists one already-encrypted invitation delivery request."
  @spec enqueue_invitation_delivery(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  defdelegate enqueue_invitation_delivery(attrs), to: InvitationQueue, as: :enqueue
end
