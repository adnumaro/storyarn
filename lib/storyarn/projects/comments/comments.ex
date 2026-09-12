defmodule Storyarn.Projects.Comments do
  @moduledoc "Project-owned contextual conversations, independent of any editor's content model."
  alias Phoenix.PubSub
  alias Storyarn.Platform
  alias Storyarn.Projects.Access
  alias Storyarn.Projects.Comments.Context
  alias Storyarn.Projects.Comments.DTO
  alias Storyarn.Projects.Comments.IdeationConversations
  alias Storyarn.Projects.Comments.Mutations
  alias Storyarn.Projects.Comments.ParticipationState
  alias Storyarn.Projects.Comments.Payload
  alias Storyarn.Projects.Comments.Queries
  alias Storyarn.Repo

  def subscribe_conversations(%{user: %{id: id}} = scope) when is_integer(id) and id > 0 do
    with :ok <- subscribe_topic(conversation_topic(id)),
         :ok <- subscribe_source_changes(scope),
         do: subscribe_participation(scope)
  end

  def subscribe_conversations(_), do: {:error, :not_found}

  def subscribe_source_changes(%{user: %{id: id}}) when is_integer(id) and id > 0, do: subscribe_topic(source_topic(id))

  def subscribe_source_changes(_), do: {:error, :not_found}

  def subscribe_participation(%{user: %{id: id}}) when is_integer(id) and id > 0,
    do: subscribe_topic(participation_topic(id))

  def subscribe_participation(_), do: {:error, :not_found}

  defp subscribe_topic(topic) do
    # The Hub may share a LiveView with the notification hook. Phoenix PubSub
    # permits duplicate registrations, so compose subscriptions idempotently.
    if topic in Registry.keys(Storyarn.PubSub, self()),
      do: :ok,
      else: PubSub.subscribe(Storyarn.PubSub, topic)
  end

  # Resolve the audience at publication time, not when a socket mounts: the
  # inbox spans projects and must also observe newly granted memberships.
  def invalidate_ideation_sources(project_id) do
    publish_to_members(project_id, &source_topic/1, {:ideation_comment_sources_changed, project_id})
  end

  def invalidate_ideation_activity(project_id) do
    publish_to_members(project_id, &conversation_topic/1, {:ideation_conversations_changed, project_id})
  end

  defp publish_to_members(project_id, topic, event) do
    if Repo.in_transaction?() do
      {:error, :comment_requires_outer_transaction}
    else
      project_id
      |> IdeationConversations.member_ids()
      |> Enum.each(&PubSub.broadcast(Storyarn.PubSub, topic.(&1), event))
    end
  end

  def restricted_comment_message_ids_query, do: IdeationConversations.restricted_message_ids()
  def readable_comment_message_ids_query(scope), do: IdeationConversations.readable_message_ids(scope)

  def list_ideation_conversations(%{user: %{id: id}} = scope, opts) when is_integer(id) and id > 0 do
    with {:ok, threads, cursor} <- IdeationConversations.list(scope, opts) do
      projects = Map.new(threads, &{&1.id, &1.project_id})
      dtos = Enum.map(thread_dtos(threads, scope), &Map.put(&1, :project_id, projects[&1.id]))
      {:ok, %{threads: dtos, next_cursor: cursor}}
    end
  end

  def list_ideation_conversations(_, _), do: {:error, :not_found}

  def set_following(scope, project_id, thread_id, following),
    do: update_participation(scope, project_id, thread_id, {:follow, following})

  def mark_thread_read(scope, project_id, thread_id, message_id),
    do: update_participation(scope, project_id, thread_id, {:read, message_id})

  defp update_participation(scope, project_id, thread_id, action) do
    with {:ok, thread} <- ParticipationState.update(scope, project_id, thread_id, action) do
      PubSub.broadcast(
        Storyarn.PubSub,
        participation_topic(scope.user.id),
        {:ideation_comment_participation_changed, project_id, thread.container_id, thread.id}
      )

      get_thread(scope, project_id, thread_id)
    end
  end

  def list_ideation_threads(scope, project_id, session_id, anchor \\ nil, opts \\ []) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(session_id) and Payload.valid_ideation_anchor?(anchor),
         {:ok, _source} <- Queries.ideation_source(scope, project_id, session_id, anchor, []) do
      {threads, cursor} = Queries.list_ideation_threads(project_id, session_id, anchor, opts)
      {:ok, %{threads: thread_dtos(threads, scope), next_cursor: cursor}}
    else
      _ -> {:error, :not_found}
    end
  end

  def create_ideation(scope, project_id, session_id, anchor, attrs) do
    scope
    |> Mutations.create_ideation(project_id, session_id, anchor, attrs)
    |> publish_and_read(scope, project_id)
  end

  def subscribe_ideation(scope, project_id, session_id) do
    with {:ok, _} <- Storyarn.Ideation.comment_source(scope, project_id, session_id, nil) do
      PubSub.subscribe(Storyarn.PubSub, ideation_topic(project_id, session_id))
    end
  end

  def unsubscribe_ideation(project_id, session_id),
    do: PubSub.unsubscribe(Storyarn.PubSub, ideation_topic(project_id, session_id))

  def list_flow_threads(scope, project_id, flow_id, opts \\ []) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id) do
      {threads, next_cursor} = Queries.list_threads(project_id, :flow, flow_id, opts)
      {:ok, %{threads: thread_dtos(threads), next_cursor: next_cursor}}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_scene_threads(scope, project_id, scene_id, opts \\ []) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(scene_id) do
      {threads, next_cursor} = Queries.list_threads(project_id, :scene, scene_id, opts)
      {:ok, %{threads: thread_dtos(threads), next_cursor: next_cursor}}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_sheet_threads(scope, project_id, sheet_id, opts \\ []) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(sheet_id) do
      {threads, next_cursor} = Queries.list_threads(project_id, :sheet, sheet_id, opts)
      {:ok, %{threads: thread_dtos(threads), next_cursor: next_cursor}}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_thread(scope, project_id, thread_id, opts \\ []) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(thread_id),
         thread when not is_nil(thread) <- Queries.thread(project_id, thread_id),
         true <- Queries.readable?(thread, scope) do
      read_thread_detail(scope, thread, opts)
    else
      _ -> {:error, :not_found}
    end
  end

  defp read_thread_detail(scope, thread, opts) do
    {messages, next_cursor} = Queries.list_messages(thread.id, opts)
    root_message = Queries.root_messages([thread.id])[thread.id]
    messages = include_root_message(messages, root_message, opts)
    mentions = Queries.mentions(Enum.map(messages, & &1.id))
    author_ids = Enum.map(messages, & &1.author_id) ++ Enum.flat_map(Map.values(mentions), & &1)
    authors = Queries.authors(author_ids)

    case thread_dtos([thread], scope) do
      [dto] ->
        # The read acknowledgement must refer to this response, not to a reply
        # committed after the messages were fetched or outside this message page.
        dto = with_read_marker(dto, thread, messages)

        {:ok,
         %{
           thread: dto,
           messages: Enum.map(messages, &DTO.message(&1, authors, Map.get(mentions, &1.id, []))),
           next_cursor: next_cursor
         }}

      _ ->
        {:error, :not_found}
    end
  end

  defp with_read_marker(dto, thread, messages) do
    if Queries.ideation?(thread),
      do: Map.put(dto, :last_message_id, Enum.max([0 | Enum.map(messages, & &1.id)])),
      else: dto
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

  def create_scene_canvas(scope, project_id, scene_id, attrs) do
    scope
    |> Mutations.create_scene_canvas(project_id, scene_id, attrs)
    |> publish_and_read(scope, project_id)
  end

  def create_sheet_canvas(scope, project_id, sheet_id, attrs) do
    scope
    |> Mutations.create_sheet_canvas(project_id, sheet_id, attrs)
    |> publish_and_read(scope, project_id)
  end

  def validate_flow_context(scope, project_id, flow_id, input) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id),
         flow when not is_nil(flow) <- Queries.flow_source(project_id, flow_id),
         {:ok, context} <- Context.normalize(input),
         {:ok, _attributes} <-
           Context.attributes(%{source_type: "flow_canvas", container_id: flow.id, project_id: project_id}, context) do
      {:ok, context}
    else
      {:error, _reason} = error -> error
      _unavailable -> {:error, :source_unavailable}
    end
  end

  def validate_sheet_context(scope, project_id, sheet_id, input) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(sheet_id),
         sheet when not is_nil(sheet) <- Queries.sheet_source(project_id, sheet_id),
         {:ok, context} <- Context.normalize(input),
         {:ok, _attributes} <-
           Context.attributes(%{source_type: "sheet_canvas", container_id: sheet.id, project_id: project_id}, context) do
      {:ok, context}
    else
      {:error, _reason} = error -> error
      _unavailable -> {:error, :source_unavailable}
    end
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

  def move(scope, project_id, thread_id, position, expected_revision, opts \\ []) do
    with {:ok, %{thread: thread}} <-
           scope
           |> Mutations.move(project_id, thread_id, position, expected_revision, opts)
           |> publish_and_read(scope, project_id) do
      {:ok, thread}
    end
  end

  def list_pins(scope, project_id, flow_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id) do
      {:ok, project_id |> Queries.list_pins(:flow, flow_id) |> thread_dtos()}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_scene_pins(scope, project_id, scene_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(scene_id) do
      {:ok, project_id |> Queries.list_pins(:scene, scene_id) |> thread_dtos()}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_sheet_pins(scope, project_id, sheet_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(sheet_id) do
      {:ok, project_id |> Queries.list_pins(:sheet, sheet_id) |> thread_dtos()}
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
         true <- Queries.readable?(thread, scope),
         true <- not is_nil(Queries.available_source(thread, scope: scope)) do
      {:ok, destination(thread)}
    else
      _ -> {:error, :not_found}
    end
  end

  def destinations(%{user: %{id: user_id}} = scope, comment_ids) when is_list(comment_ids) do
    if Payload.valid_id?(user_id) do
      comment_ids
      |> Enum.filter(&Payload.valid_id?/1)
      |> Enum.uniq()
      |> then(&Queries.destinations(user_id, &1))
      |> Enum.filter(fn row ->
        row.project_role |> Access.effective_role(row.workspace_role) |> Access.can?(:view)
      end)
      |> Map.new(fn row ->
        {{row.destination.project_id, row.message_id}, destination_row(row.destination)}
      end)
      |> Map.merge(IdeationConversations.destinations(scope, Enum.filter(comment_ids, &Payload.valid_id?/1)))
    else
      %{}
    end
  end

  def destinations(_scope, _comment_ids), do: %{}

  def subscribe_flow(scope, project_id, flow_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(flow_id) do
      PubSub.subscribe(Storyarn.PubSub, flow_topic(project_id, flow_id))
    else
      _ -> {:error, :not_found}
    end
  end

  def unsubscribe_flow(project_id, flow_id) do
    PubSub.unsubscribe(Storyarn.PubSub, flow_topic(project_id, flow_id))
  end

  def subscribe_scene(scope, project_id, scene_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(scene_id) do
      PubSub.subscribe(Storyarn.PubSub, scene_topic(project_id, scene_id))
    else
      _ -> {:error, :not_found}
    end
  end

  def unsubscribe_scene(project_id, scene_id) do
    PubSub.unsubscribe(Storyarn.PubSub, scene_topic(project_id, scene_id))
  end

  def subscribe_sheet(scope, project_id, sheet_id) do
    with {:ok, _project} <- authorize_read(scope, project_id),
         true <- Payload.valid_id?(sheet_id) do
      PubSub.subscribe(Storyarn.PubSub, sheet_topic(project_id, sheet_id))
    else
      _ -> {:error, :not_found}
    end
  end

  def unsubscribe_sheet(project_id, sheet_id) do
    PubSub.unsubscribe(Storyarn.PubSub, sheet_topic(project_id, sheet_id))
  end

  defp authorize_read(scope, project_id) do
    case Access.authorize(scope, project_id, :view) do
      {:ok, project, _membership} -> {:ok, project}
      _ -> {:error, :not_found}
    end
  end

  defp thread_dtos(threads, scope \\ nil) do
    authors = Queries.authors(Enum.flat_map(threads, &[&1.author_id, &1.resolved_by_id]))
    previews = Queries.root_messages(Enum.map(threads, & &1.id))
    {ideation, canonical} = Enum.split_with(threads, &Queries.ideation?/1)

    available =
      Map.merge(
        Queries.available_sources(canonical),
        IdeationConversations.available_sources(scope, Enum.map(ideation, & &1.id))
      )

    contexts = Context.available_many(canonical)
    # Revalidate the page in one batch after loading previews: the source or
    # membership may disappear during this read. Never reuse an earlier audience
    # check or fall back to a historical preview for restricted sources.
    dtos =
      threads
      |> Enum.reject(&(Queries.ideation?(&1) and is_nil(available[&1.id])))
      |> Enum.map(&DTO.thread(&1, authors, available[&1.id], previews[&1.id], contexts[&1.id]))

    ParticipationState.decorate(dtos, scope)
  end

  defp include_root_message(messages, nil, _opts), do: messages

  defp include_root_message(messages, root, opts) do
    if is_nil(opts[:cursor]) and not Enum.any?(messages, &(&1.id == root.id)),
      do: [root | messages],
      else: messages
  end

  defp publish_and_read({:ok, result}, scope, project_id) do
    if result.notification, do: Platform.publish_notification_delivery(result.notification)

    if result.changed?, do: publish_change(project_id, result)

    get_thread(scope, project_id, result.thread_id)
  end

  defp publish_and_read({:error, _} = error, _scope, _project_id), do: error

  defp publish_change(project_id, %{source_type: source_type, container_id: flow_id})
       when source_type in ["flow_node", "flow_canvas"] do
    PubSub.broadcast(Storyarn.PubSub, flow_topic(project_id, flow_id), {:flow_comments_changed, flow_id})
  end

  defp publish_change(project_id, %{source_type: "scene_canvas", container_id: scene_id}) do
    PubSub.broadcast(Storyarn.PubSub, scene_topic(project_id, scene_id), {:scene_comments_changed, scene_id})
  end

  defp publish_change(project_id, %{source_type: "sheet_canvas", container_id: sheet_id}) do
    PubSub.broadcast(Storyarn.PubSub, sheet_topic(project_id, sheet_id), {:sheet_comments_changed, sheet_id})
  end

  defp publish_change(project_id, %{source_type: type, container_id: session_id})
       when type in ["ideation_session", "ideation_idea", "ideation_group"] do
    invalidate_ideation_activity(project_id)
    publish_ideation_change(project_id, session_id)
  end

  defp publish_ideation_change(project_id, session_id) do
    PubSub.broadcast(Storyarn.PubSub, ideation_topic(project_id, session_id), {:ideation_comments_changed, session_id})
  end

  defp conversation_topic(user_id), do: "ideation:conversations:user:#{user_id}"
  defp source_topic(user_id), do: "ideation:comment_sources:user:#{user_id}"
  defp participation_topic(user_id), do: "ideation:comment_participation:user:#{user_id}"

  defp destination(%{source_type: source_type} = thread) when source_type in ["flow_node", "flow_canvas"] do
    %{
      surface: "flow",
      flow_id: thread.container_id,
      node_id: destination_node_id(thread),
      thread_id: thread.id
    }
  end

  defp destination(%{source_type: "scene_canvas"} = thread) do
    %{surface: "scene", scene_id: thread.container_id, thread_id: thread.id}
  end

  defp destination(%{source_type: "sheet_canvas"} = thread) do
    %{surface: "sheet", sheet_id: thread.container_id, thread_id: thread.id}
  end

  defp destination(%{source_type: type} = thread) when type in ~w(ideation_session ideation_idea ideation_group) do
    %{surface: "brainstorming", session_id: thread.container_id, thread_id: thread.id}
  end

  defp destination_node_id(%{source_type: "flow_node", source_id: id}), do: id

  defp destination_node_id(%{context_type: "flow_node"} = thread) do
    case Context.available(thread) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp destination_node_id(_thread), do: nil

  defp destination_row(%{source_type: source_type} = destination) when source_type in ["flow_node", "flow_canvas"] do
    destination
    |> Map.put(:surface, "flow")
    |> Map.drop([:source_type, :scene_id, :sheet_id])
  end

  defp destination_row(%{source_type: "scene_canvas"} = destination) do
    destination
    |> Map.put(:surface, "scene")
    |> Map.drop([:source_type, :flow_id, :node_id, :sheet_id])
  end

  defp destination_row(%{source_type: "sheet_canvas"} = destination) do
    destination
    |> Map.put(:surface, "sheet")
    |> Map.drop([:source_type, :flow_id, :node_id, :scene_id])
  end

  defp flow_topic(project_id, flow_id), do: "project:#{project_id}:flow:#{flow_id}:comments"
  defp scene_topic(project_id, scene_id), do: "project:#{project_id}:scene:#{scene_id}:comments"
  defp sheet_topic(project_id, sheet_id), do: "project:#{project_id}:sheet:#{sheet_id}:comments"
  defp ideation_topic(project_id, session_id), do: "project:#{project_id}:ideation:#{session_id}:comments"
end
