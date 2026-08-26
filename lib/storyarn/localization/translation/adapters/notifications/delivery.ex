defmodule Storyarn.Localization.Translation.Adapters.Notifications.Delivery do
  @moduledoc false

  alias Storyarn.Platform

  @spec deliver_async_result(integer() | nil, pos_integer(), map()) ::
          {:ok, term()} | {:error, term()}
  def deliver_async_result(requested_by_id, project_id, attrs) do
    Platform.deliver_async_result(requested_by_id, project_id, attrs)
  end

  @spec publish_committed(term()) :: :ok
  def publish_committed(outcome), do: Platform.publish_notification_delivery(outcome)
end
