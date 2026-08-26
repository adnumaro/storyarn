defmodule Storyarn.Localization.Languages.Adapters.Notifications.Delivery do
  @moduledoc false

  alias Storyarn.Platform

  @spec deliver_content_activity(pos_integer(), pos_integer(), atom(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  def deliver_content_activity(actor_id, project_id, action, entity_type, entity) do
    Platform.deliver_content_activity_by_ids(actor_id, project_id, action, entity_type, entity)
  end

  @spec publish_committed(term()) :: :ok
  def publish_committed(outcome), do: Platform.publish_notification_delivery(outcome)
end
