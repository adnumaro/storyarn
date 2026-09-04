defmodule Storyarn.Projects.Comments.DTO do
  @moduledoc false
  alias Storyarn.Platform.Shared.HtmlUtils

  def member(nil), do: %{id: nil, display_name: "Deleted user", avatar_url: nil}

  def member(user) do
    %{id: user.id, display_name: user.display_name || "Member", avatar_url: user.avatar_url}
  end

  def source_label(%{name: name}) when is_binary(name), do: HtmlUtils.strip_and_truncate(name, 120)

  def source_label(node) do
    data = node.data || %{}
    candidate = data["name"] || data["text"] || data["label"]
    label = if is_binary(candidate), do: HtmlUtils.strip_and_truncate(candidate, 120)
    label || "#{String.capitalize(node.type)} ##{node.id}"
  end

  def thread(thread, authors, source, root_message) do
    %{
      id: thread.id,
      status: thread.status,
      revision: thread.revision,
      message_count: thread.message_count,
      position: position(thread),
      root_message_id: if(root_message, do: root_message.id),
      preview: if(root_message, do: String.slice(root_message.body, 0, 160), else: ""),
      created_at: timestamp(thread.inserted_at),
      last_activity_at: timestamp(thread.last_activity_at),
      resolved_at: timestamp(thread.resolved_at),
      resolved_by: if(thread.resolved_by_id, do: member(authors[thread.resolved_by_id])),
      author: member(authors[thread.author_id]),
      source: %{
        type: thread.source_type,
        id: thread.source_id,
        flow_id: thread.container_id,
        label: if(source, do: source_label(source), else: thread.source_label),
        status: if(source, do: "available", else: "unavailable")
      }
    }
  end

  def message(message, authors, mention_ids) do
    %{
      id: message.id,
      thread_id: message.thread_id,
      parent_id: message.parent_id,
      body: message.body,
      author: member(authors[message.author_id]),
      mentions: Enum.map(mention_ids, &member(authors[&1])),
      inserted_at: timestamp(message.inserted_at)
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
  defp position(%{position_x: nil}), do: nil
  defp position(thread), do: %{x: thread.position_x, y: thread.position_y}
end
