defmodule Storyarn.Projects.Comments do
  @moduledoc "Project-owned contextual conversations, independent of any editor's content model."
  alias Phoenix.PubSub
  alias Storyarn.Platform
  alias Storyarn.Projects.Access
  alias Storyarn.Projects.Comments.DTO
  alias Storyarn.Projects.Comments.Mutations
  alias Storyarn.Projects.Comments.Payload
  alias Storyarn.Projects.Comments.Queries

  def list_flow_threads(scope, project_id, flow_id, opts \\ []) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id) do
      {threads, next_cursor} = Queries.list_threads(project_id, flow_id, opts)
      {:ok, %{threads: thread_dtos(threads), next_cursor: next_cursor}}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_thread(scope, project_id, thread_id, opts \\ []) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(thread_id),
         thread when not is_nil(thread) <- Queries.thread(project_id, thread_id) do
      {messages, next_cursor} = Queries.list_messages(thread.id, opts)
      root_message = Queries.root_messages([thread.id])[thread.id]
      messages = include_root_message(messages, root_message, opts)
      mentions = Queries.mentions(Enum.map(messages, & &1.id))
      author_ids = Enum.map(messages, & &1.author_id) ++ Enum.flat_map(Map.values(mentions), & &1)
      authors = Queries.authors(author_ids)

      {:ok,
       %{
         thread: hd(thread_dtos([thread])),
         messages: Enum.map(messages, &DTO.message(&1, authors, Map.get(mentions, &1.id, []))),
         next_cursor: next_cursor
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def create(scope, project_id, flow_id, node_id, attrs) do
    scope
    |> Mutations.create(project_id, flow_id, node_id, attrs)
    |> publish_and_read(scope, project_id)
  end

  def create_canvas(scope, project_id, flow_id, attrs) do
    scope
    |> Mutations.create_canvas(project_id, flow_id, attrs)
    |> publish_and_read(scope, project_id)
  end

  def reply(scope, project_id, thread_id, attrs) do
    scope
    |> Mutations.reply(project_id, thread_id, attrs)
    |> publish_and_read(scope, project_id)
  end

  def set_status(scope, project_id, thread_id, status, expected_revision) do
    with {:ok, %{thread: thread}} <-
           scope
           |> Mutations.set_status(project_id, thread_id, status, expected_revision)
           |> publish_and_read(scope, project_id) do
      {:ok, thread}
    end
  end

  def move(scope, project_id, thread_id, position, expected_revision) do
    with {:ok, %{thread: thread}} <-
           scope
           |> Mutations.move(project_id, thread_id, position, expected_revision)
           |> publish_and_read(scope, project_id) do
      {:ok, thread}
    end
  end

  def list_pins(scope, project_id, flow_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id) do
      {:ok, project_id |> Queries.list_pins(flow_id) |> thread_dtos()}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_members(scope, project_id) do
    with {:ok, project} <- authorize_read(scope, project_id) do
      {:ok, Enum.map(Queries.members(project), &DTO.member/1)}
    end
  end

  def flow_counts(scope, project_id, flow_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id) do
      {:ok, Queries.open_counts(project_id, flow_id)}
    else
      _ -> {:error, :not_found}
    end
  end

  def destination(scope, project_id, comment_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(comment_id),
         message when not is_nil(message) <- Queries.message(project_id, comment_id),
         thread when not is_nil(thread) <- Queries.thread(project_id, message.thread_id),
         true <- Queries.source_available?(thread) do
      node_id = if thread.source_type == "flow_node", do: thread.source_id
      {:ok, %{flow_id: thread.container_id, node_id: node_id, thread_id: thread.id}}
    else
      _ -> {:error, :not_found}
    end
  end

  def destinations(%{user: %{id: user_id}}, comment_ids) when is_list(comment_ids) do
    if Payload.valid_id?(user_id) do
      comment_ids
      |> Enum.filter(&Payload.valid_id?/1)
      |> Enum.uniq()
      |> then(&Queries.destinations(user_id, &1))
      |> Enum.filter(fn row ->
        row.project_role |> Access.effective_role(row.workspace_role) |> Access.can?(:view)
      end)
      |> Map.new(fn row -> {{row.destination.project_id, row.message_id}, row.destination} end)
    else
      %{}
    end
  end

  def destinations(_scope, _comment_ids), do: %{}

  def subscribe_flow(scope, project_id, flow_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id) do
      PubSub.subscribe(Storyarn.PubSub, topic(project_id, flow_id))
    else
      _ -> {:error, :not_found}
    end
  end

  def unsubscribe_flow(project_id, flow_id) do
    PubSub.unsubscribe(Storyarn.PubSub, topic(project_id, flow_id))
  end

  defp authorize_read(scope, project_id) do
    case Access.authorize(scope, project_id, :view) do
      {:ok, project, _membership} -> {:ok, project}
      _ -> {:error, :not_found}
    end
  end

  defp thread_dtos(threads) do
    authors = Queries.authors(Enum.flat_map(threads, &[&1.author_id, &1.resolved_by_id]))
    previews = Queries.root_messages(Enum.map(threads, & &1.id))
    available = Queries.available_sources(threads)
    Enum.map(threads, &DTO.thread(&1, authors, available[&1.id], previews[&1.id]))
  end

  defp include_root_message(messages, nil, _opts), do: messages

  defp include_root_message(messages, root, opts) do
    if is_nil(opts[:cursor]) and not Enum.any?(messages, &(&1.id == root.id)),
      do: [root | messages],
      else: messages
  end

  defp publish_and_read({:ok, result}, scope, project_id) do
    if result.notification, do: Platform.publish_notification_delivery(result.notification)

    if result.changed? do
      PubSub.broadcast(Storyarn.PubSub, topic(project_id, result.flow_id), {:flow_comments_changed, result.flow_id})
    end

    get_thread(scope, project_id, result.thread_id)
  end

  defp publish_and_read({:error, _} = error, _scope, _project_id), do: error
  defp topic(project_id, flow_id), do: "project:#{project_id}:flow:#{flow_id}:comments"
end
