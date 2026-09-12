defmodule StoryarnWeb.CommentLive.Index do
  @moduledoc "Authenticated, cross-project review of conversations created in the editors."
  use StoryarnWeb, :live_view

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.CommentLive.Params
  alias StoryarnWeb.Helpers.Authorize

  @refresh_interval 30_000
  @access_events ~w(project_membership_changed project_ownership_transferred workspace_membership_changed workspace_ownership_transferred)a
  @comment_events ~w(comment_conversations_changed ideation_conversations_changed ideation_comment_sources_changed)a

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Projects.subscribe_comment_conversations(socket.assigns.current_scope)
      schedule_refresh()
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Comments"))
     |> assign(:project, nil)
     |> assign(:project_id, nil)
     |> assign(:page_count, 1)
     |> assign(:message_history_bound, nil)
     |> assign(:source_refresh_pending, false)
     |> assign(:subscribed_projects, MapSet.new())
     |> assign(:subscribed_workspaces, MapSet.new())
     |> assign(:hub_projects, %{})
     |> assign(:hub, %{
       threads: [],
       nextCursor: nil,
       counts: %{all: 0, open: 0, resolved: 0},
       filters: Params.defaults(),
       workspaces: [],
       projects: [],
       conversation: empty_conversation(),
       selectedProjectId: nil,
       selectedThreadId: nil,
       contextUrl: nil,
       error: nil
     })}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(:page_count, Params.page_count(params["pages"]))
     |> put_hub(%{
       filters: Params.filters(params),
       selectedProjectId: Params.positive(params["project"]),
       selectedThreadId: Params.positive(params["thread"])
     })
     |> refresh()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.WorkspaceLayout.workspace
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
      onboarding={@onboarding}
      content_mode="fill"
      comments_active={true}
    >
      <.vue
        v-component="live/comments/Hub"
        v-socket={@socket}
        v-inject="workspace-layout"
        id="comments-hub"
        state={@hub}
        current-user-id={@current_scope.user.id}
      />
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
    """
  end

  @impl true
  def handle_event("hub_filter", params, socket) do
    {:noreply,
     socket
     |> assign(:page_count, 1)
     |> put_hub(%{filters: Params.filters(params)})
     |> clear_selection()
     |> patch()}
  end

  def handle_event("hub_select", params, socket) do
    {:noreply,
     socket
     |> put_hub(%{
       selectedProjectId: Params.positive(params["project_id"]),
       selectedThreadId: Params.positive(params["thread_id"])
     })
     |> load_selection()
     |> patch()}
  end

  def handle_event("hub_clear_selection", _params, socket), do: {:noreply, socket |> clear_selection() |> patch()}
  def handle_event("hub_refresh", _params, socket), do: {:reply, %{ok: true}, refresh(socket)}

  def handle_event("hub_load_more", _params, socket) do
    socket =
      if socket.assigns.hub.nextCursor && socket.assigns.page_count < Params.max_pages() do
        socket |> assign(:page_count, socket.assigns.page_count + 1) |> patch()
      else
        refresh(socket)
      end

    {:reply, %{ok: true}, socket}
  end

  def handle_event("comments_load_messages", _params, socket) do
    cursor = socket.assigns.hub.conversation.messageNextCursor
    {:noreply, if(cursor, do: load_selection(socket, cursor), else: load_selection(socket))}
  end

  def handle_event(event, params, socket) when event in ~w(comments_reply comments_set_status) do
    Authorize.with_authorization(
      socket,
      :edit_content,
      &mutate(event, params, &1),
      fn current, _reason -> failure(refresh(current), :not_found) end
    )
  end

  # This surface never creates a source or a thread, even through forged events.
  def handle_event(_event, _params, socket), do: failure(refresh(socket), :not_found)

  @impl true
  def handle_info({event, _payload}, socket) when event in @access_events or event in @comment_events,
    do: {:noreply, refresh(socket)}

  def handle_info({:ideation_comment_participation_changed, _project_id, _session_id, _thread_id}, socket),
    do: {:noreply, refresh(socket)}

  def handle_info({:dashboard_invalidate, _source}, socket) do
    if !socket.assigns.source_refresh_pending do
      Process.send_after(self(), :refresh_comment_hub_sources, 150)
    end

    {:noreply, assign(socket, :source_refresh_pending, true)}
  end

  def handle_info(:refresh_comment_hub_sources, socket),
    do: {:noreply, socket |> assign(:source_refresh_pending, false) |> refresh()}

  def handle_info(:refresh_comment_hub, socket) do
    schedule_refresh()
    {:noreply, refresh(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh(socket), do: socket |> load_options() |> load_threads() |> load_selection()

  defp load_options(socket) do
    scope = socket.assigns.current_scope
    workspaces = scope |> Workspaces.list_workspaces() |> Enum.map(& &1.workspace)

    projects =
      Enum.flat_map(workspaces, fn workspace ->
        workspace.id
        |> Projects.list_projects_for_workspace(scope)
        |> Enum.filter(&Projects.can?(Projects.effective_role(&1.project_role, &1.workspace_role), :view))
        |> Enum.map(fn %{project: project} ->
          %{
            id: project.id,
            name: project.name,
            slug: project.slug,
            workspace_id: workspace.id,
            workspace_slug: workspace.slug
          }
        end)
      end)

    socket
    |> subscribe_access_changes(workspaces, projects)
    |> assign(:workspaces, workspaces)
    |> assign(:hub_projects, Map.new(projects, &{&1.id, &1}))
    |> put_hub(%{
      workspaces: Enum.map(workspaces, &Map.take(&1, [:id, :name])),
      projects: Enum.map(projects, &Map.take(&1, [:id, :name, :workspace_id]))
    })
  end

  defp subscribe_access_changes(socket, workspaces, projects) do
    if connected?(socket) do
      workspace_ids = MapSet.new(workspaces, & &1.id)
      project_ids = MapSet.new(projects, & &1.id)

      workspace_ids
      |> MapSet.difference(socket.assigns.subscribed_workspaces)
      |> Enum.each(fn id ->
        Workspaces.subscribe_workspace_membership_changes(id)
        Workspaces.subscribe_workspace_ownership_changes(id)
      end)

      project_ids
      |> MapSet.difference(socket.assigns.subscribed_projects)
      |> Enum.each(fn id ->
        Projects.subscribe_project_membership_changes(id)
        Projects.subscribe_project_ownership_changes(id)
        Collaboration.subscribe_dashboard(id)
      end)

      socket
      |> assign(:subscribed_workspaces, MapSet.union(socket.assigns.subscribed_workspaces, workspace_ids))
      |> assign(:subscribed_projects, MapSet.union(socket.assigns.subscribed_projects, project_ids))
    else
      socket
    end
  end

  defp load_threads(socket) do
    options = Params.options(socket.assigns.hub.filters)

    case pages(socket.assigns.current_scope, options, socket.assigns.page_count) do
      {:ok, result} ->
        at_limit = socket.assigns.page_count == Params.max_pages() and not is_nil(result.next_cursor)

        put_hub(socket, %{
          threads: result.threads,
          nextCursor: if(at_limit, do: nil, else: result.next_cursor),
          counts: result.counts,
          error: if(at_limit, do: gettext("Narrow your search or filters to see more conversations."))
        })

      _ ->
        socket
        |> clear_selection()
        |> put_hub(%{
          threads: [],
          nextCursor: nil,
          counts: %{all: 0, open: 0, resolved: 0},
          error: gettext("Comments could not be loaded. Please try again.")
        })
    end
  end

  # Rebuild loaded pages from fresh authorized queries, so revocation cannot
  # leave rows from an earlier page in the client after a refresh/load-more.
  defp pages(scope, options, remaining) do
    case Projects.list_comment_conversations(scope, options) do
      {:ok, %{next_cursor: cursor} = page} when remaining > 1 and cursor not in [nil, false] ->
        with {:ok, rest} <- pages(scope, Keyword.put(options, :cursor, cursor), remaining - 1) do
          {:ok, %{page | threads: page.threads ++ rest.threads, next_cursor: rest.next_cursor}}
        end

      result ->
        result
    end
  end

  defp load_selection(socket, cursor \\ nil) do
    %{selectedProjectId: project_id, selectedThreadId: thread_id} = socket.assigns.hub
    scope = socket.assigns.current_scope
    previous_bound = retained_history_bound(socket, project_id, thread_id)

    with true <- is_integer(project_id) and is_integer(thread_id),
         true <- Map.has_key?(socket.assigns.hub_projects, project_id),
         {:ok, bound} <- history_bound(scope, project_id, thread_id, cursor, previous_bound),
         {:ok, detail} <- read_history(scope, project_id, thread_id, bound),
         {:ok, members} <- Projects.list_comment_members(scope, project_id),
         url = context_url(socket, project_id, detail.thread),
         {:ok, _project, membership} <- Projects.authorize(scope, project_id, :view) do
      conversation = %{
        empty_conversation()
        | open: true,
          thread: detail.thread,
          messages: detail.messages,
          messageNextCursor: detail.next_cursor,
          selectedSourceId: detail.thread.source.id,
          selectedSourceLabel: detail.thread.source.label,
          members: members,
          canComment:
            detail.thread.source.status == "available" and
              Projects.can?(membership.role, :edit_content)
      }

      socket
      |> assign(:project_id, project_id)
      |> assign(:message_history_bound, bound)
      |> put_hub(%{
        conversation: conversation,
        contextUrl: url
      })
    else
      _ -> clear_selection(socket)
    end
  end

  defp retained_history_bound(socket, project_id, thread_id) do
    current = socket.assigns.hub.conversation

    if current.thread && current.thread.id == thread_id && socket.assigns.project_id == project_id,
      do: socket.assigns.message_history_bound
  end

  defp history_bound(_scope, _project_id, _thread_id, nil, bound), do: {:ok, bound}

  defp history_bound(scope, project_id, thread_id, cursor, _bound) do
    with {:ok, page} <- Projects.get_comment_thread(scope, project_id, thread_id, cursor: cursor) do
      {:ok, page.next_cursor || 0}
    end
  end

  # The bound comes only from a previously authorized server page. Re-read
  # retained history on refresh so both its audience and author DTOs stay fresh.
  # A zero bound means the reader reached the beginning of the conversation.
  defp read_history(scope, project_id, thread_id, bound, cursor \\ nil) do
    case Projects.get_comment_thread(scope, project_id, thread_id, cursor: cursor) do
      {:ok, %{next_cursor: next} = page} when is_integer(bound) and is_integer(next) and next > bound ->
        with {:ok, older} <- read_history(scope, project_id, thread_id, bound, next) do
          messages = Enum.sort_by(Enum.uniq_by(page.messages ++ older.messages, & &1.id), & &1.id)
          {:ok, %{page | messages: messages, next_cursor: older.next_cursor}}
        end

      result ->
        result
    end
  end

  defp mutate(event, params, socket) do
    %{selectedProjectId: project_id, selectedThreadId: selected_id} = socket.assigns.hub
    id = Params.positive(params["thread_id"])
    scope = socket.assigns.current_scope

    with true <- is_integer(id) and id == selected_id,
         {:ok, %{thread: %{source: %{status: "available"}}}} <- Projects.get_comment_thread(scope, project_id, id),
         {:ok, _result} <- mutation(event, scope, project_id, id, params) do
      {:reply, %{ok: true}, refresh(socket)}
    else
      {:error, reason} -> failure(refresh(socket), reason)
      _ -> failure(refresh(socket), :not_found)
    end
  end

  defp mutation("comments_reply", scope, project_id, id, params) do
    Projects.reply_to_comment_thread(
      scope,
      project_id,
      id,
      Map.take(params, ~w(body parent_id client_request_id mention_user_ids))
    )
  end

  defp mutation("comments_set_status", scope, project_id, id, params),
    do:
      Projects.set_comment_thread_status(
        scope,
        project_id,
        id,
        params["status"],
        Params.positive(params["expected_revision"])
      )

  defp context_url(socket, project_id, thread) do
    with %{workspace_slug: workspace, slug: project} <- socket.assigns.hub_projects[project_id],
         {:ok, destination} <-
           Projects.comment_destination(socket.assigns.current_scope, project_id, thread.root_message_id) do
      destination_url(destination, workspace, project)
    else
      _ -> nil
    end
  end

  defp destination_url(%{surface: "flow"} = destination, workspace, project),
    do:
      ~p"/workspaces/#{workspace}/projects/#{project}/flows/#{destination.flow_id}?#{%{thread: destination.thread_id}}"

  defp destination_url(%{surface: "scene"} = destination, workspace, project),
    do:
      ~p"/workspaces/#{workspace}/projects/#{project}/scenes/#{destination.scene_id}?#{%{thread: destination.thread_id}}"

  defp destination_url(%{surface: "sheet"} = destination, workspace, project),
    do:
      ~p"/workspaces/#{workspace}/projects/#{project}/sheets/#{destination.sheet_id}?#{%{thread: destination.thread_id}}"

  defp destination_url(%{surface: "brainstorming"} = destination, workspace, project),
    do:
      ~p"/workspaces/#{workspace}/projects/#{project}/brainstorming/#{destination.session_id}?#{%{thread: destination.thread_id}}"

  defp destination_url(_, _, _), do: nil

  defp patch(socket) do
    hub = socket.assigns.hub
    query = Params.query(hub.filters, hub.selectedProjectId, hub.selectedThreadId, socket.assigns.page_count)
    push_patch(socket, to: ~p"/comments?#{query}")
  end

  defp clear_selection(socket) do
    socket
    |> assign(:project_id, nil)
    |> assign(:message_history_bound, nil)
    |> put_hub(%{
      selectedProjectId: nil,
      selectedThreadId: nil,
      conversation: empty_conversation(),
      contextUrl: nil
    })
  end

  defp empty_conversation do
    %{
      open: false,
      presentation: "workspace",
      threads: [],
      nextCursor: nil,
      thread: nil,
      messages: [],
      messageNextCursor: nil,
      members: [],
      canComment: false,
      selectedSourceId: nil,
      selectedSourceLabel: nil,
      statusFilter: "all",
      error: nil
    }
  end

  defp failure(socket, reason) do
    error =
      if reason == :stale,
        do: gettext("This conversation changed. Please try again."),
        else: gettext("This conversation is no longer available or you do not have permission to change it.")

    conversation = %{socket.assigns.hub.conversation | error: error}
    {:reply, %{ok: false, error: error}, put_hub(socket, %{conversation: conversation})}
  end

  defp put_hub(socket, changes), do: assign(socket, :hub, Map.merge(socket.assigns.hub, changes))
  defp schedule_refresh, do: Process.send_after(self(), :refresh_comment_hub, @refresh_interval)
end
