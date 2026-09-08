defmodule StoryarnWeb.IdeationLive.Sidebar do
  @moduledoc false
  use StoryarnWeb, :live_view

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.IdeationLive.Handlers.SessionHandlers
  alias StoryarnWeb.IdeationLive.Helpers.BoardData
  alias StoryarnWeb.IdeationLive.Helpers.Params
  alias StoryarnWeb.IdeationLive.Helpers.Replies
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @impl true
  def mount(_, session, socket) do
    if locale = session["locale"], do: Gettext.put_locale(Storyarn.Gettext, locale)
    scope = session["current_scope"]
    project_id = session["project_id"]
    workspace_id = session["workspace_id"]

    if connected?(socket) do
      Ideation.subscribe_sessions(scope, project_id)
      Phoenix.PubSub.subscribe(Storyarn.PubSub, ProjectChromeHelpers.shell_topic(project_id))
      Projects.subscribe_project_ownership_changes(project_id)
      Projects.subscribe_project_membership_changes(project_id)
      Workspaces.subscribe_workspace_ownership_changes(workspace_id)
      Workspaces.subscribe_workspace_membership_changes(workspace_id)
    end

    socket =
      assign(socket,
        current_scope: scope,
        project_id: project_id,
        workspace_id: workspace_id,
        base_url: session["base_url"],
        epoch: Ecto.UUID.generate(),
        board: BoardData.empty(),
        error: nil,
        filters: %{session_status: :open, session_before: nil, idea_before: nil}
      )

    {:ok, load(socket), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full">
      <.vue
        v-component="live/ideation/BoardSidebar"
        v-socket={@socket}
        id="brainstorming-sidebar"
        class="h-full"
        base-url={@base_url}
        board={Map.merge(@board, %{epoch: @epoch, loading: false, error: @error})}
      />
    </div>
    """
  end

  @impl true
  def handle_event("browse_sessions", params, socket) do
    case Params.optional_id(params["before_id"]) do
      {:ok, before_id} ->
        filters = %{
          socket.assigns.filters
          | session_status: Params.filter(params["status"], [:open, :archived, :replaced], :open),
            session_before: before_id
        }

        {:reply, %{status: "ok"}, socket |> assign(:filters, filters) |> load()}

      {:error, reason} ->
        {:reply, Replies.error(reason), socket}
    end
  end

  def handle_event(event, params, socket) when event in ~w(create_session recover_session purge_session) do
    Authorize.with_authorization(
      socket,
      :edit_content,
      &write(&1, event, params),
      fn socket, reason -> {:reply, Replies.error(reason), load(socket)} end
    )
  end

  def handle_event("sync_board", _, socket), do: {:reply, %{status: "ok"}, load(socket)}

  @impl true
  def handle_info({:ideation_sessions_changed, _}, socket), do: {:noreply, load(socket)}

  def handle_info({event, %{project_id: id}}, %{assigns: %{project_id: id}} = socket)
      when event in [:project_membership_changed, :project_ownership_transferred], do: {:noreply, load(socket)}

  def handle_info({event, %{workspace_id: id}}, %{assigns: %{workspace_id: id}} = socket)
      when event in [:workspace_membership_changed, :workspace_ownership_transferred], do: {:noreply, load(socket)}

  def handle_info({:project_restored, _}, socket) do
    socket = socket |> assign(:epoch, Ecto.UUID.generate()) |> load()
    {:noreply, push_event(socket, "brainstorming_reset", %{reason: "project_restored", epoch: socket.assigns.epoch})}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp write(socket, event, params) do
    if params["epoch"] == socket.assigns.epoch do
      params = session_params(event, params)
      result = SessionHandlers.run(event, socket.assigns.current_scope, socket.assigns.project_id, params)
      socket = socket |> load() |> navigate_created(event, result)
      {:reply, Replies.result(result), socket}
    else
      {:reply, Replies.error(:stale_board), socket}
    end
  end

  defp session_params("create_session", params),
    do: Map.merge(params, %{"title" => gettext("Untitled session"), "preset" => "openPreset"})

  defp session_params(_, params), do: params

  # The page owns navigation, as in the other tool sidebars. Keeping the same
  # Board LiveView also preserves in-flight reads and the sticky child's reply.
  defp navigate_created(socket, "create_session", {:ok, %{id: id}}) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "project:#{socket.assigns.project_id}:ideation-navigation:#{node(socket.transport_pid)}:#{inspect(socket.transport_pid)}",
      {:open_ideation_session, %{project_id: socket.assigns.project_id, session_id: id}}
    )

    socket
  end

  defp navigate_created(socket, _, _), do: socket

  defp load(socket) do
    case BoardData.load(socket.assigns.current_scope, socket.assigns.project_id, nil, socket.assigns.filters) do
      {:ok, data} ->
        assign(socket, board: data, error: nil)

      {:error, reason} when reason in [:unauthorized, :not_found] ->
        socket
        |> assign(board: BoardData.empty(), error: "unauthorized", epoch: Ecto.UUID.generate())
        |> push_event("brainstorming_reset", %{reason: "access_changed"})

      _ ->
        assign(socket, :error, "unavailable")
    end
  end
end
