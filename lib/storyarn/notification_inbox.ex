defmodule Storyarn.NotificationInbox do
  @moduledoc """
  Application composition for the authorized notification inbox.

  Projects supplies current comment-source visibility; Platform owns recipient
  access, persistence and read-state changes. The same server-built predicate
  is applied inside SQL for listing, counting and both read operations. No
  content authorization callback runs from Platform back into a producer.
  """

  import Ecto.Query

  alias Storyarn.Platform
  alias Storyarn.Projects

  def list_notifications(scope, opts \\ []) do
    Platform.list_notifications(scope, Keyword.put(opts, :comment_visibility, comment_visibility(scope)))
  end

  def unread_notification_count(scope) do
    Platform.unread_notification_count(scope, comment_visibility: comment_visibility(scope))
  end

  def mark_notification_read(scope, notification_id) do
    Platform.mark_notification_read(scope, notification_id, comment_visibility: comment_visibility(scope))
  end

  def mark_all_notifications_read(scope) do
    Platform.mark_all_notifications_read(scope, comment_visibility: comment_visibility(scope))
  end

  defp comment_visibility(%{user: %{id: _}} = scope) do
    restricted =
      from(message in subquery(Projects.restricted_comment_message_ids_query()),
        where: message.id == parent_as(:notification).entity_id,
        select: true,
        limit: 1
      )

    readable =
      from(message in subquery(Projects.readable_comment_message_ids_query(scope)),
        where: message.id == parent_as(:notification).entity_id,
        select: true,
        limit: 1
      )

    # A scalar lookup keeps authorization tied to this message. PostgreSQL can
    # otherwise turn a correlated EXISTS into a hashed, inbox-wide readable set.
    dynamic(not coalesce(subquery(restricted), false) or coalesce(subquery(readable), false))
  end

  defp comment_visibility(_scope), do: dynamic(false)
end
