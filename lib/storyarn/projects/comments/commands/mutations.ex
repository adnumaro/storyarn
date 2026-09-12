defmodule Storyarn.Projects.Comments.Mutations do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Access
  alias Storyarn.Projects.Comments.Context
  alias Storyarn.Projects.Comments.DTO
  alias Storyarn.Projects.Comments.Mention
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Payload
  alias Storyarn.Projects.Comments.Queries
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Repo

  defguardp valid_thread_id?(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807

  def create_ideation(scope, project_id, session_id, anchor, attrs) do
    with {:ok, payload} <- Payload.normalize(attrs),
         true <- Payload.valid_id?(session_id) and Payload.valid_ideation_anchor?(anchor) do
      target = {:create_ideation, session_id, anchor}

      transact_request(scope, project_id, payload, target, fn project, actor_id, hash ->
        source = lock_ideation_source!(scope, project.id, session_id, anchor)
        validate_mentions!(project, payload.mention_user_ids)
        {type, _id} = Payload.ideation_anchor(session_id, anchor)

        thread =
          Repo.insert!(%Thread{
            project_id: project.id,
            author_id: actor_id,
            source_type: type,
            source_id: source.id,
            container_id: session_id,
            ideation_session_id: session_id,
            ideation_idea_id: if(type == "ideation_idea", do: source.id),
            ideation_group_id: if(type == "ideation_group", do: source.id),
            source_inserted_at: source.inserted_at,
            source_recovery_identity: source.recovery_identity,
            source_label:
              %{"ideation_session" => "Session", "ideation_idea" => "Idea", "ideation_group" => "Group"}[type],
            last_activity_at: TimeHelpers.now()
          })

        insert_message(thread, actor_id, nil, payload, hash, [])
      end)
    else
      false -> {:error, :invalid_request}
      {:error, _} = error -> error
    end
  end

  defp lock_ideation_source!(scope, project_id, session_id, anchor) do
    case Queries.ideation_source(scope, project_id, session_id, anchor, lock: :share) do
      {:ok, source} -> source
      _ -> Repo.rollback(:not_found)
    end
  end

  def create(scope, project_id, flow_id, node_id, attrs) do
    with {:ok, payload} <- Payload.normalize(attrs),
         {:ok, position} <- Payload.position(Payload.value(attrs, :position)),
         true <- Payload.valid_id?(flow_id) and Payload.valid_id?(node_id) do
      payload = Map.put(payload, :position, position)

      transact_request(scope, project_id, payload, {:create, flow_id, node_id}, fn project, actor_id, request_hash ->
        create_thread!(project, actor_id, flow_id, node_id, payload, request_hash)
      end)
    else
      false -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def create_canvas(scope, project_id, flow_id, attrs) do
    with {:ok, payload} <- Payload.normalize(attrs),
         {:ok, payload} <- contextual_payload(payload, attrs),
         {:ok, position} <- Payload.position(Payload.value(attrs, :position), required: true),
         true <- Payload.valid_id?(flow_id) do
      payload = Map.put(payload, :position, position)

      transact_request(scope, project_id, payload, {:create_canvas, flow_id}, fn project, actor_id, request_hash ->
        create_canvas_thread!(project, actor_id, flow_id, payload, request_hash)
      end)
    else
      false -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def create_scene_canvas(scope, project_id, scene_id, attrs) do
    with {:ok, payload} <- Payload.normalize(attrs),
         {:ok, payload} <- contextual_payload(payload, attrs),
         {:ok, position} <- Payload.scene_position(Payload.value(attrs, :position)),
         true <- Payload.valid_id?(scene_id) do
      payload = Map.put(payload, :position, position)
      target = {:create_scene_canvas, scene_id}

      transact_request(scope, project_id, payload, target, fn project, actor_id, request_hash ->
        create_scene_canvas_thread!(project, actor_id, scene_id, payload, request_hash)
      end)
    else
      false -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def create_sheet_canvas(scope, project_id, sheet_id, attrs) do
    with {:ok, payload} <- Payload.normalize(attrs),
         {:ok, payload} <- contextual_payload(payload, attrs),
         {:ok, position} <- Payload.sheet_position(Payload.value(attrs, :position)),
         true <- Payload.valid_id?(sheet_id) do
      payload = Map.put(payload, :position, position)
      target = {:create_sheet_canvas, sheet_id}

      transact_request(scope, project_id, payload, target, fn project, actor_id, request_hash ->
        create_sheet_canvas_thread!(project, actor_id, sheet_id, payload, request_hash)
      end)
    else
      false -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def reply(scope, project_id, thread_id, attrs) do
    with {:ok, payload} <- Payload.normalize(attrs),
         parent_id = Payload.value(attrs, :parent_id),
         true <- Payload.valid_id?(thread_id) and Payload.valid_id?(parent_id) do
      transact_request(scope, project_id, payload, {:reply, thread_id, parent_id}, fn project, actor_id, request_hash ->
        reply_to_thread!(project, actor_id, thread_id, parent_id, payload, request_hash, scope)
      end)
    else
      false -> {:error, :invalid_parent}
      {:error, _} = error -> error
    end
  end

  def set_status(scope, project_id, thread_id, status, expected_revision)
      when status in ["open", "resolved"] and is_integer(expected_revision) and expected_revision > 0 and
             valid_thread_id?(thread_id) do
    transact(scope, project_id, fn project, actor_id ->
      thread = lock_available_thread!(project.id, thread_id, scope)
      if thread.revision != expected_revision, do: Repo.rollback(:stale)

      if thread.status == status do
        result(thread, nil, false)
      else
        now = TimeHelpers.now()

        thread
        |> change(%{
          status: status,
          revision: thread.revision + 1,
          resolved_at: if(status == "resolved", do: now),
          resolved_by_id: if(status == "resolved", do: actor_id),
          last_activity_at: now
        })
        |> Repo.update!()

        result(thread, nil, true)
      end
    end)
  end

  def set_status(_scope, _project_id, _thread_id, _status, _revision), do: {:error, :invalid_status}

  def move(scope, project_id, thread_id, position, expected_revision, opts \\ [])

  def move(scope, project_id, thread_id, position, expected_revision, opts)
      when valid_thread_id?(thread_id) and is_integer(expected_revision) and expected_revision > 0 do
    with {:ok, position} <- Payload.position(position, required: true),
         {:ok, context} <- normalize_context_option(opts) do
      transact(scope, project_id, fn project, _actor_id ->
        move_thread!(project.id, thread_id, position, expected_revision, context, scope)
      end)
    end
  end

  def move(_scope, _project_id, _thread_id, _position, _revision, _opts), do: {:error, :invalid_position}

  defp move_thread!(project_id, thread_id, position, expected_revision, context, scope) do
    thread = Queries.thread(project_id, thread_id) || Repo.rollback(:not_found)
    Queries.available_source(thread, lock: :share, scope: scope) || Repo.rollback(:source_unavailable)
    if Queries.ideation?(thread), do: Repo.rollback(:invalid_position)
    validate_position_for_thread!(thread, position)

    attributes =
      thread
      |> context_attributes!(context)
      |> update_flow_offset(thread, position)
      |> Map.merge(%{position_x: position.x, position_y: position.y})

    # Lock referenced content before the thread, matching FK deletion order.
    thread = Queries.thread(project_id, thread_id, lock: :update) || Repo.rollback(:not_found)
    if thread.revision != expected_revision, do: Repo.rollback(:stale)
    changed? = Enum.any?(attributes, fn {key, value} -> Map.get(thread, key) != value end)

    if changed? do
      thread
      |> change(Map.put(attributes, :revision, thread.revision + 1))
      |> Repo.update!()
    end

    result(thread, nil, changed?)
  end

  defp validate_position_for_thread!(%Thread{source_type: "scene_canvas"}, position) do
    case Payload.normalized_position(position) do
      {:ok, _position} -> :ok
      {:error, :invalid_position} -> Repo.rollback(:invalid_position)
    end
  end

  defp validate_position_for_thread!(%Thread{source_type: "sheet_canvas"}, position) do
    case Payload.sheet_position(position) do
      {:ok, _position} -> :ok
      {:error, :invalid_position} -> Repo.rollback(:invalid_position)
    end
  end

  defp validate_position_for_thread!(_thread, _position), do: :ok

  defp contextual_payload(payload, attrs) do
    if Map.has_key?(attrs, :context) or Map.has_key?(attrs, "context") do
      with {:ok, context} <- Context.normalize(Payload.value(attrs, :context)) do
        {:ok, Map.put(payload, :context, context)}
      end
    else
      {:ok, payload}
    end
  end

  defp normalize_context_option(opts) do
    case Keyword.fetch(opts, :context) do
      :error -> {:ok, :retain}
      {:ok, value} -> Context.normalize(value)
    end
  end

  defp context_attributes!(_thread, :retain), do: %{}

  defp context_attributes!(thread, context) do
    case Context.attributes(thread, context, lock: :share) do
      {:ok, attributes} -> attributes
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp update_flow_offset(attributes, thread, position) do
    candidate = struct(thread, attributes)

    case candidate.context_type == "flow_node" && Context.available(candidate, lock: :share) do
      %{position_x: x, position_y: y} ->
        case Payload.position(%{x: position.x - x, y: position.y - y}, required: true) do
          {:ok, offset} -> Map.merge(attributes, %{context_offset_x: offset.x, context_offset_y: offset.y})
          {:error, reason} -> Repo.rollback(reason)
        end

      _ ->
        attributes
    end
  end

  defp insert_contextual_thread!(thread, context) do
    attributes =
      thread
      |> context_attributes!(context)
      |> update_flow_offset(thread, %{x: thread.position_x, y: thread.position_y})

    thread |> change(attributes) |> Repo.insert!()
  end

  defp transact(scope, project_id, fun) do
    if Repo.in_transaction?() do
      {:error, :comment_requires_outer_transaction}
    else
      Repo.transaction(fn -> authorize_and_run(scope, project_id, fun) end)
    end
  end

  defp authorize_and_run(scope, project_id, fun) do
    case Access.authorize_locked(scope, project_id, :edit_content) do
      {:ok, project, _membership} -> fun.(project, scope.user.id)
      {:error, :unauthorized} -> Repo.rollback(:unauthorized)
      {:error, _} -> Repo.rollback(:not_found)
    end
  end

  defp transact_request(scope, project_id, payload, target, fun) do
    request_hash = Payload.fingerprint(payload, target)

    transact(scope, project_id, fn project, actor_id ->
      with_request(scope, project.id, actor_id, payload, request_hash, fn ->
        fun.(project, actor_id, request_hash)
      end)
    end)
  end

  defp create_thread!(project, actor_id, flow_id, node_id, payload, request_hash) do
    flow = Queries.flow_source(project.id, flow_id, lock: :share) || Repo.rollback(:source_unavailable)
    node = Queries.source(project.id, flow_id, node_id, lock: :share) || Repo.rollback(:source_unavailable)
    validate_mentions!(project, payload.mention_user_ids)
    offset = payload.position || %{x: 16.0, y: 16.0}
    position = node_comment_position!(node, offset)

    thread =
      insert_contextual_thread!(
        %Thread{
          project_id: project.id,
          author_id: actor_id,
          source_type: "flow_canvas",
          source_id: flow.id,
          flow_canvas_id: flow.id,
          container_id: flow_id,
          source_inserted_at: flow.inserted_at,
          source_label: DTO.source_label(flow),
          position_x: position.x,
          position_y: position.y,
          last_activity_at: TimeHelpers.now()
        },
        %{type: "flow_node", id: to_string(node.id), offset: offset}
      )

    insert_message(thread, actor_id, nil, payload, request_hash, [])
  end

  defp node_comment_position!(node, offset) do
    case Payload.position(%{x: node.position_x + offset.x, y: node.position_y + offset.y}, required: true) do
      {:ok, position} -> position
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp create_canvas_thread!(project, actor_id, flow_id, payload, request_hash) do
    flow = Queries.flow_source(project.id, flow_id, lock: :share) || Repo.rollback(:source_unavailable)
    validate_mentions!(project, payload.mention_user_ids)

    thread =
      insert_contextual_thread!(
        %Thread{
          project_id: project.id,
          author_id: actor_id,
          source_type: "flow_canvas",
          source_id: flow.id,
          flow_canvas_id: flow.id,
          container_id: flow.id,
          source_inserted_at: flow.inserted_at,
          source_label: DTO.source_label(flow),
          position_x: payload.position.x,
          position_y: payload.position.y,
          last_activity_at: TimeHelpers.now()
        },
        Map.get(payload, :context)
      )

    insert_message(thread, actor_id, nil, payload, request_hash, [])
  end

  defp create_scene_canvas_thread!(project, actor_id, scene_id, payload, request_hash) do
    scene = Queries.scene_source(project.id, scene_id, lock: :share) || Repo.rollback(:source_unavailable)
    validate_mentions!(project, payload.mention_user_ids)

    thread =
      insert_contextual_thread!(
        %Thread{
          project_id: project.id,
          author_id: actor_id,
          source_type: "scene_canvas",
          source_id: scene.id,
          scene_canvas_id: scene.id,
          container_id: scene.id,
          source_inserted_at: scene.inserted_at,
          source_label: DTO.source_label(scene),
          position_x: payload.position.x,
          position_y: payload.position.y,
          last_activity_at: TimeHelpers.now()
        },
        Map.get(payload, :context)
      )

    insert_message(thread, actor_id, nil, payload, request_hash, [])
  end

  defp create_sheet_canvas_thread!(project, actor_id, sheet_id, payload, request_hash) do
    sheet = Queries.sheet_source(project.id, sheet_id, lock: :share) || Repo.rollback(:source_unavailable)
    validate_mentions!(project, payload.mention_user_ids)

    thread =
      insert_contextual_thread!(
        %Thread{
          project_id: project.id,
          author_id: actor_id,
          source_type: "sheet_canvas",
          source_id: sheet.id,
          sheet_canvas_id: sheet.id,
          container_id: sheet_id,
          source_inserted_at: sheet.inserted_at,
          source_label: DTO.source_label(sheet),
          position_x: payload.position.x,
          position_y: payload.position.y,
          last_activity_at: TimeHelpers.now()
        },
        Map.get(payload, :context)
      )

    insert_message(thread, actor_id, nil, payload, request_hash, [])
  end

  defp reply_to_thread!(project, actor_id, thread_id, parent_id, payload, request_hash, scope) do
    thread = lock_available_thread!(project.id, thread_id, scope)
    if thread.status != "open", do: Repo.rollback(:thread_resolved)
    parent = Queries.message(project.id, parent_id)
    if is_nil(parent) or parent.thread_id != thread.id, do: Repo.rollback(:invalid_parent)
    validate_mentions!(project, payload.mention_user_ids)
    insert_message(thread, actor_id, parent_id, payload, request_hash, List.wrap(parent.author_id))
  end

  defp with_request(scope, project_id, actor_id, payload, request_hash, fun) do
    key = Enum.join(["comment", project_id, actor_id, payload.client_request_id], ":")
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

    case Queries.existing_request(project_id, actor_id, payload.client_request_id) do
      nil ->
        fun.()

      %Message{request_hash: ^request_hash} = message ->
        thread = Queries.thread(project_id, message.thread_id)
        if not Queries.readable?(thread, scope), do: Repo.rollback(:not_found)
        result(thread, nil, false)

      _ ->
        Repo.rollback(:idempotency_conflict)
    end
  end

  defp lock_available_thread!(project_id, thread_id, scope) do
    thread = Queries.thread(project_id, thread_id) || Repo.rollback(:not_found)

    Queries.available_source(thread, lock: :share, scope: scope) || Repo.rollback(:source_unavailable)

    Queries.thread(project_id, thread_id, lock: :update) || Repo.rollback(:not_found)
  end

  defp validate_mentions!(project, ids) do
    allowed = project |> Queries.members() |> MapSet.new(& &1.id)
    if !Enum.all?(ids, &MapSet.member?(allowed, &1)), do: Repo.rollback(:invalid_mention)
  end

  defp insert_message(thread, actor_id, parent_id, payload, request_hash, reply_recipients) do
    message =
      Repo.insert!(%Message{
        project_id: thread.project_id,
        thread_id: thread.id,
        author_id: actor_id,
        parent_id: parent_id,
        body: payload.body,
        client_request_id: payload.client_request_id,
        request_hash: request_hash
      })

    mentions = Enum.map(payload.mention_user_ids, &%{message_id: message.id, user_id: &1})
    Repo.insert_all(Mention, mentions)

    thread
    |> change(%{
      message_count: thread.message_count + 1,
      revision: thread.revision + 1,
      last_activity_at: TimeHelpers.now()
    })
    |> Repo.update!()

    followers =
      if Queries.ideation?(thread), do: Storyarn.Projects.Comments.ParticipationState.followers(thread.id), else: []

    recipients =
      Enum.map(followers, &%{user_id: &1, kind: "comment_followed"}) ++
        Enum.map(reply_recipients, &%{user_id: &1, kind: "comment_reply"}) ++
        Enum.map(payload.mention_user_ids, &%{user_id: &1, kind: "comment_mention"})

    # The source share lock fences private-mode/deletion changes. All eligible
    # brainstorming anchors are currently project-readable; notification reads
    # independently reauthorize that source before listing or counting it.
    delivery = Platform.deliver_comment_activity(actor_id, thread.project_id, message.id, recipients)

    case delivery do
      {:ok, notification} ->
        result(thread, notification, true)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp result(thread, notification, changed?) do
    %{
      thread_id: thread.id,
      source_type: thread.source_type,
      container_id: thread.container_id,
      notification: notification,
      changed?: changed?
    }
  end
end
