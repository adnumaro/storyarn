defmodule Storyarn.Localization.NotificationDelivery do
  @moduledoc false

  alias Storyarn.Platform

  @spec deliver_content_activity(pos_integer(), pos_integer(), atom(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  def deliver_content_activity(actor_id, project_id, action, entity_type, entity) do
    Platform.deliver_content_activity_by_ids(actor_id, project_id, action, entity_type, entity)
  end

  @spec deliver_async_result(integer() | nil, pos_integer(), map()) ::
          {:ok, term()} | {:error, term()}
  def deliver_async_result(requested_by_id, project_id, attrs) do
    Platform.deliver_async_result(requested_by_id, project_id, attrs)
  end

  @spec publish_committed(term()) :: :ok
  def publish_committed(outcome), do: Platform.publish_notification_delivery(outcome)
end
